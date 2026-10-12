import AppKit
import Combine

final class MenuBarController: NSObject {
    private let store: PingStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleWidget: (NSStatusBarButton) -> Void
    private let showFloatingWidget: () -> Void
    private var updates: AnyCancellable?

    init(store: PingStore, toggleWidget: @escaping (NSStatusBarButton) -> Void,
         showFloatingWidget: @escaping () -> Void) {
        self.store = store
        self.toggleWidget = toggleWidget
        self.showFloatingWidget = showFloatingWidget
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Published changes arrive before mutation; refresh on the next main turn.
        updates = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(item)
    }

    private func refresh() {
        guard let button = item.button else { return }
        let sample = store.endpoints.first.flatMap { store.results(for: $0.id).last }
        let title: String
        let color: NSColor
        if let sample {
            if let ms = sample.latencyMs {
                title = String(format: "%.0f ms", ms)
                color = ms < 50 ? .systemGreen : (ms < 100 ? .systemYellow : .systemRed)
            } else {
                title = "∞ ms"
                color = .systemRed
            }
        } else {
            title = "— ms"
            color = .secondaryLabelColor
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ])
        button.toolTip = "NetMon · \(title)"
        button.setAccessibilityLabel("NetMon ping latency, \(title)")
    }

    @objc private func toggleWindow() {
        guard let button = item.button else { return }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let menu = NSMenu()
            let floatingItem = NSMenuItem(title: "Switch to Floating Widget",
                                          action: #selector(switchToFloatingWidget),
                                          keyEquivalent: "")
            floatingItem.target = self
            menu.addItem(floatingItem)
            menu.addItem(.separator())
            let quitItem = NSMenuItem(title: "Quit NetMon",
                                     action: #selector(NSApplication.terminate(_:)),
                                     keyEquivalent: "q")
            quitItem.target = NSApp
            menu.addItem(quitItem)
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }
        toggleWidget(button)
    }

    @objc private func switchToFloatingWidget() {
        // Let menu tracking finish before removing its status item.
        let action = showFloatingWidget
        DispatchQueue.main.async { action() }
    }
}
