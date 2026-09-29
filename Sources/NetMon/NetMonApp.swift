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
    private var menuBarController: MenuBarController?
    private var modeObserver: NSObjectProtocol?
    private let menuBarModeKey = "netmon.menuBarMode"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menuBarMode = UserDefaults.standard.object(forKey: menuBarModeKey) as? Bool ?? true
        windowController = NetMonWindowController(showOnLaunch: !menuBarMode)
        setMenuBarMode(menuBarMode)
        modeObserver = NotificationCenter.default.addObserver(forName: .netMonToggleMenuBar,
                                                              object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.setMenuBarMode(self.menuBarController == nil)
        }

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

    private func setMenuBarMode(_ enabled: Bool) {
        guard let windowController else { return }
        UserDefaults.standard.set(enabled, forKey: menuBarModeKey)
        if enabled {
            if menuBarController == nil {
                menuBarController = MenuBarController(store: windowController.store, toggleWidget: { [weak self] button in
                    self?.windowController?.toggleFromMenuBar(button)
                }, showFloatingWidget: { [weak self] in
                    self?.setMenuBarMode(false)
                })
            }
            windowController.window?.orderOut(nil)
        } else {
            menuBarController = nil
            windowController.window?.level = windowController.store.alwaysOnTop ? .floating : .normal
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let modeObserver { NotificationCenter.default.removeObserver(modeObserver) }
    }
}

extension Notification.Name {
    static let netMonToggleMenuBar = Notification.Name("netmon.toggleMenuBar")
    static let netMonToggleExpand = Notification.Name("netmon.toggleExpand")
    static let netMonMinimize = Notification.Name("netmon.minimize")
    static let netMonResetView = Notification.Name("netmon.resetView")
}
