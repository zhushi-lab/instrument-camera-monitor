import AppKit
import Foundation

final class AppLauncher: NSObject, NSApplicationDelegate {
    private let capture = Process()
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else {
            NSAlert(error: NSError(domain: "IntervalCamera", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "应用资源不完整，请重新安装。"])).runModal()
            NSApp.terminate(nil)
            return
        }
        capture.executableURL = URL(fileURLWithPath: "/bin/bash")
        capture.arguments = [resources.appendingPathComponent("capture_with_imagesnap.sh").path]
        capture.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                if self?.quitting == true {
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
        do {
            try capture.run()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard capture.isRunning else { return .terminateNow }
        quitting = true
        capture.terminate()
        return .terminateLater
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let launcher = AppLauncher()
app.delegate = launcher
app.run()
