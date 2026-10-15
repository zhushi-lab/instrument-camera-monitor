import AppKit
import Darwin
import Foundation

final class CaptureMenu: NSObject {
    private let capturePID: pid_t
    private let folder: URL
    private let mailSettingsScript: URL?
    private var statusItem: NSStatusItem?
    private var emailItem: NSMenuItem?
    private var emailSettingsProcess: Process?

    init(capturePID: pid_t, folder: URL, mailSettingsScript: URL?) {
        self.capturePID = capturePID
        self.folder = folder
        self.mailSettingsScript = mailSettingsScript
    }

    func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "📷 拍照中"
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开照片文件夹", action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        if mailSettingsScript != nil {
            let email = NSMenuItem(title: "邮件提醒设置…", action: #selector(changeEmail), keyEquivalent: "")
            email.target = self
            menu.addItem(email)
            emailItem = email
        }

        let stop = NSMenuItem(title: "停止拍照", action: #selector(stopCapture), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        item.menu = menu
        statusItem = item
        app.run()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(folder)
    }

    @objc private func changeEmail() {
        guard let mailSettingsScript, emailSettingsProcess == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [mailSettingsScript.path]
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.emailSettingsProcess === finished else { return }
                self.emailSettingsProcess = nil
                self.emailItem?.isEnabled = true
            }
        }
        do {
            try process.run()
            emailSettingsProcess = process
            emailItem?.isEnabled = false
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func stopCapture() {
        _ = Darwin.kill(capturePID, SIGTERM)
        statusItem?.button?.title = "📷 停止中"
    }
}

guard (3...4).contains(CommandLine.arguments.count),
      let pid = Int32(CommandLine.arguments[1]), pid > 0 else {
    fputs("Usage: CaptureMenu <capture-pid> <photo-folder> [mail-settings-script]\n", stderr)
    exit(2)
}

let controller = CaptureMenu(capturePID: pid,
                             folder: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
                             mailSettingsScript: CommandLine.arguments.count == 4
                               ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil)
controller.run()
