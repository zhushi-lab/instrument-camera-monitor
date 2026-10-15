import AppKit
import Foundation

// The rectangle is stored as fractions of the original image, measured from
// its top-left corner. This keeps the OCR area unchanged when the preview zooms.
final class SelectionView: NSView {
    let photo: NSImage
    var selection = NSRect(x: 0.35, y: 0.35, width: 0.30, height: 0.20) {
        didSet { needsDisplay = true }
    }
    private enum DragMode { case create, move, resize(Int) }
    private var mode: DragMode?
    private var anchor = NSPoint.zero
    private var startSelection = NSRect.zero
    private var startPoint = NSPoint.zero

    init(photo: NSImage, size: NSSize) {
        self.photo = photo
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        return NSPoint(x: min(max(p.x / bounds.width, 0), 1),
                       y: min(max(p.y / bounds.height, 0), 1))
    }

    private func displayRect(_ r: NSRect) -> NSRect {
        NSRect(x: r.minX * bounds.width, y: r.minY * bounds.height,
               width: r.width * bounds.width, height: r.height * bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        // draw(in:) respects this view's flipped (top-left) coordinates.
        photo.draw(in: bounds)
        let r = displayRect(selection)
        NSColor.black.withAlphaComponent(0.42).setFill()
        [NSRect(x: 0, y: 0, width: bounds.width, height: r.minY),
         NSRect(x: 0, y: r.maxY, width: bounds.width, height: bounds.height - r.maxY),
         NSRect(x: 0, y: r.minY, width: r.minX, height: r.height),
         NSRect(x: r.maxX, y: r.minY, width: bounds.width - r.maxX, height: r.height)]
            .forEach { $0.fill() }
        NSColor.systemYellow.setStroke()
        let border = NSBezierPath(rect: r)
        border.lineWidth = 2
        border.stroke()
        NSColor.white.setFill()
        for c in corners(r) {
            let handle = NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            NSBezierPath(ovalIn: handle).fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(ovalIn: handle).stroke()
        }
    }

    private func corners(_ r: NSRect) -> [NSPoint] {
        [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
         NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)]
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        let screen = NSPoint(x: p.x * bounds.width, y: p.y * bounds.height)
        let handles = corners(displayRect(selection))
        if let i = handles.firstIndex(where: { hypot($0.x - screen.x, $0.y - screen.y) <= 12 }) {
            mode = .resize(i)
            let opposite = [3, 2, 1, 0][i]
            anchor = corners(selection)[opposite]
        } else if selection.contains(p) {
            mode = .move
            startSelection = selection
            startPoint = p
        } else {
            mode = .create
            anchor = p
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode else { return }
        let p = point(event)
        switch mode {
        case .move:
            selection.origin.x = min(max(startSelection.minX + p.x - startPoint.x, 0), 1 - selection.width)
            selection.origin.y = min(max(startSelection.minY + p.y - startPoint.y, 0), 1 - selection.height)
        case .create, .resize:
            let minWidth = 8 / bounds.width
            let minHeight = 8 / bounds.height
            let x0 = min(anchor.x, p.x)
            let y0 = min(anchor.y, p.y)
            selection = NSRect(x: x0, y: y0,
                               width: max(abs(p.x - anchor.x), minWidth),
                               height: max(abs(p.y - anchor.y), minHeight))
            if selection.maxX > 1 { selection.origin.x = 1 - selection.width }
            if selection.maxY > 1 { selection.origin.y = 1 - selection.height }
        }
    }

    override func mouseUp(with event: NSEvent) { mode = nil }
}

final class PickerController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let view: SelectionView
    let scroll: NSScrollView
    let baseSize: NSSize
    var accepted = false
    var retryRequested = false

    init(photo: NSImage) {
        let ratio = photo.size.width / max(photo.size.height, 1)
        baseSize = NSSize(width: 1000, height: 1000 / ratio)
        view = SelectionView(photo: photo, size: baseSize)
        scroll = NSScrollView(frame: NSRect(x: 20, y: 85, width: 1000, height: 560))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "选择数字识别区域"
        window.center()
        window.delegate = self
        window.level = .floating
        scroll.documentView = view
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        window.contentView?.addSubview(scroll)

        let instructions = NSTextField(labelWithString: "在框外拖出新框；拖动框内可移动；拖动四角可改变大小。只框住目标数字。")
        instructions.frame = NSRect(x: 20, y: 657, width: 1000, height: 24)
        window.contentView?.addSubview(instructions)

        let zoomLabel = NSTextField(labelWithString: "预览放大")
        zoomLabel.frame = NSRect(x: 20, y: 45, width: 75, height: 22)
        window.contentView?.addSubview(zoomLabel)
        let zoom = NSSlider(value: 1, minValue: 1, maxValue: 6, target: self, action: #selector(changeZoom(_:)))
        zoom.frame = NSRect(x: 95, y: 43, width: 245, height: 26)
        zoom.numberOfTickMarks = 6
        zoom.allowsTickMarkValuesOnly = true
        window.contentView?.addSubview(zoom)
        let hint = NSTextField(labelWithString: "放大后可滚动照片，方便精确框选。")
        hint.frame = NSRect(x: 355, y: 45, width: 375, height: 22)
        window.contentView?.addSubview(hint)

        let retry = NSButton(title: "重新拍照", target: self, action: #selector(retryPicking))
        retry.frame = NSRect(x: 690, y: 25, width: 115, height: 32)
        window.contentView?.addSubview(retry)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelPicking))
        cancel.frame = NSRect(x: 810, y: 25, width: 90, height: 32)
        window.contentView?.addSubview(cancel)
        let confirm = NSButton(title: "使用此区域", target: self, action: #selector(acceptPicking))
        confirm.frame = NSRect(x: 900, y: 25, width: 120, height: 32)
        confirm.keyEquivalent = "\r"
        window.contentView?.addSubview(confirm)
    }

    @objc func changeZoom(_ sender: NSSlider) {
        let scale = CGFloat(Int(sender.doubleValue.rounded()))
        view.frame.size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        view.needsDisplay = true
        let mid = NSPoint(x: view.selection.midX * view.bounds.width,
                          y: view.selection.midY * view.bounds.height)
        let visible = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: NSPoint(x: max(0, mid.x - visible.width / 2),
                                              y: max(0, mid.y - visible.height / 2)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc func cancelPicking() { NSApp.stopModal(withCode: .abort) }
    @objc func retryPicking() {
        retryRequested = true
        NSApp.stopModal(withCode: .abort)
    }
    @objc func acceptPicking() {
        guard view.selection.width * baseSize.width >= 8,
              view.selection.height * baseSize.height >= 8 else {
            NSSound.beep()
            return
        }
        accepted = true
        NSApp.stopModal(withCode: .OK)
    }
    func windowWillClose(_ notification: Notification) { NSApp.stopModal(withCode: .abort) }
}

guard CommandLine.arguments.count == 2,
      let photo = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("usage: RegionPicker PROBE_IMAGE\n", stderr)
    exit(1)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let picker = PickerController(photo: photo)
picker.window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
_ = app.runModal(for: picker.window)
if picker.retryRequested { exit(3) }
guard picker.accepted else { exit(2) }
let r = picker.view.selection
print(String(format: "%.6f,%.6f,%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"),
             Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)))
