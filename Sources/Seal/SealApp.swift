import SwiftUI
import AppKit

extension Notification.Name {
    static let sealOpenPanel = Notification.Name("seal.openPanel")
    static let sealRefresh = Notification.Name("seal.refresh")
    static let sealResign = Notification.Name("seal.resign")
    static let sealOpenPath = Notification.Name("seal.openPath")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--appearance"), args.indices.contains(index + 1) {
            if args[index + 1] == "dark" {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            } else if args[index + 1] == "light" {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        // Development aid: render the app's own window to PNG without screen-recording access.
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            let output = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                if let window = NSApp.windows.first, let view = window.contentView {
                    let bounds = view.bounds
                    if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
                        view.cacheDisplay(in: bounds, to: rep)
                        if let data = rep.representation(using: .png, properties: [:]) {
                            try? data.write(to: URL(fileURLWithPath: output))
                        }
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        NotificationCenter.default.post(name: .sealOpenPath, object: URL(fileURLWithPath: first))
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct SealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…") {
                    NotificationCenter.default.post(name: .sealOpenPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("刷新检查") {
                    NotificationCenter.default.post(name: .sealRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("签名") {
                Button("快速重新签名") {
                    NotificationCenter.default.post(name: .sealResign, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }
    }
}
