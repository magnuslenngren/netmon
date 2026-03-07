import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// Widget dimensions – single source of truth
// ---------------------------------------------------------------------------
let kWidgetWidth:         CGFloat = 150
let kWidgetHeight:        CGFloat = 80
let kWidgetCompactHeight: CGFloat = 26
let kWidgetPad:           CGFloat = 16
let kWindowFrameDefaultsKey = "netmon.windowFrame"

// ---------------------------------------------------------------------------
// NetMonWindowController
// ---------------------------------------------------------------------------
class NetMonWindowController: NSWindowController {

    let store = PingStore()

    convenience init() {
        let window = GlassWindow(width: kWidgetWidth, height: kWidgetHeight)
        self.init(window: window)
        window.delegate = self

        let dark = NSAppearance(named: .darkAqua)
        window.appearance = dark

        let root = ContentView()
            .environmentObject(self.store)
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = dark
        window.contentView = hosting

        applyResizeConstraints(isCompact: store.isCompact, window: window)
        if !restoreWindowFrame(window) {
            positionTopRight(window)
        }
        if store.isCompact {
            applyCompactHeight(window)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func restoreWindowFrame(_ window: NSWindow) -> Bool {
        guard let frameString = UserDefaults.standard.string(forKey: kWindowFrameDefaultsKey) else {
            return false
        }
        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else { return false }
        window.setFrame(frame, display: true)
        return true
    }

    private func saveWindowFrame(_ window: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: kWindowFrameDefaultsKey)
    }

    private func applyResizeConstraints(isCompact: Bool, window: NSWindow) {
        if isCompact {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
        window.minSize = NSSize(width: kWidgetWidth, height: isCompact ? kWidgetCompactHeight : kWidgetHeight)
        window.maxSize = NSSize(width: .greatestFiniteMagnitude,
                                height: isCompact ? kWidgetCompactHeight : .greatestFiniteMagnitude)
    }

    private func applyCompactHeight(_ window: NSWindow) {
        var frame = window.frame
        frame.origin.y += frame.height - kWidgetCompactHeight // keep top edge pinned
        frame.size.height = kWidgetCompactHeight
        window.setFrame(frame, display: true, animate: false)
    }

    private func positionTopRight(_ window: NSWindow) {
        let sv = primaryVisibleFrame()
        var frame = window.frame
        frame.origin.x = sv.maxX - frame.width - kWidgetPad
        frame.origin.y = sv.maxY - frame.height - kWidgetPad
        window.setFrame(frame, display: true)
    }
}

func primaryVisibleFrame() -> NSRect {
    // The menu bar screen always has the lowest y-origin (it's the "bottom" of the
    // multi-monitor coordinate space in AppKit). NSScreen.main tracks mouse focus
    // and is NOT reliable. Use the screen whose frame contains origin (0,0) instead.
    let screen = NSScreen.screens.first(where: { $0.frame.contains(.zero) })
              ?? NSScreen.screens[0]
    return screen.visibleFrame
}

func resetNetMonWindowView(window: NSWindow, isCompact: Bool) {
    UserDefaults.standard.removeObject(forKey: kWindowFrameDefaultsKey)
    UserDefaults.standard.removeObject(forKey: "netmon.lastExpandedHeight")

    let targetHeight = isCompact ? kWidgetCompactHeight : kWidgetHeight
    var frame = window.frame
    frame.size = NSSize(width: kWidgetWidth, height: targetHeight)

    let sv = primaryVisibleFrame()
    // Snap fully to top-right of visible frame (just below menu bar clock/date area).
    frame.origin.x = sv.maxX - frame.width
    frame.origin.y = sv.maxY - frame.height
    window.setFrame(frame, display: true, animate: true)
}

extension NetMonWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        saveWindowFrame(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window else { return }
        saveWindowFrame(window)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window else { return }
        applyResizeConstraints(isCompact: store.isCompact, window: window)
    }
}

// ---------------------------------------------------------------------------
// GlassWindow
// ---------------------------------------------------------------------------
class GlassWindow: NSWindow {
    init(width: CGFloat, height: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask:   [.borderless, .resizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = true
        level                       = .floating
        collectionBehavior          = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed        = false
    }
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}
