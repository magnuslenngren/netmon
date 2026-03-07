import SwiftUI
import AppKit

@main
struct NetMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NetMonWindowController?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowController = NetMonWindowController()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }
            switch key {
            case "e":
                NotificationCenter.default.post(name: .netMonToggleExpand, object: nil)
                return nil
            case "m":
                NotificationCenter.default.post(name: .netMonMinimize, object: nil)
                return nil
            case "r":
                NotificationCenter.default.post(name: .netMonResetView, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

extension Notification.Name {
    static let netMonToggleExpand = Notification.Name("netmon.toggleExpand")
    static let netMonMinimize = Notification.Name("netmon.minimize")
    static let netMonResetView = Notification.Name("netmon.resetView")
}
