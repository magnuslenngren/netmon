import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// Widget dimensions – single source of truth
// ---------------------------------------------------------------------------
let kWidgetWidth:         CGFloat = 150
let kWidgetHeight:        CGFloat = 80
let kWidgetCompactHeight: CGFloat = 34
let kWidgetPad:           CGFloat = 16

// ---------------------------------------------------------------------------
// NetMonWindowController
// ---------------------------------------------------------------------------
class NetMonWindowController: NSWindowController {

    let store = PingStore()

    convenience init() {
        let window = GlassWindow(width: kWidgetWidth, height: kWidgetHeight)
        self.init(window: window)

        let dark = NSAppearance(named: .darkAqua)
        window.appearance = dark

        let root = ContentView()
            .environmentObject(self.store)
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = dark
        window.contentView = hosting

        positionTopRight(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func positionTopRight(_ window: NSWindow) {
        // The menu bar screen always has the lowest y-origin (it's the "bottom" of the
        // multi-monitor coordinate space in AppKit). NSScreen.main tracks mouse focus
        // and is NOT reliable. Use the screen whose frame contains origin (0,0) instead.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(.zero) })
                  ?? NSScreen.screens[0]
        let sv = screen.visibleFrame
        let x  = sv.maxX - kWidgetWidth  - kWidgetPad
        let y  = sv.maxY - kWidgetHeight - kWidgetPad
        window.setFrame(NSRect(x: x, y: y, width: kWidgetWidth, height: kWidgetHeight),
                        display: true)
    }
}

// ---------------------------------------------------------------------------
// GlassWindow
// ---------------------------------------------------------------------------
class GlassWindow: NSWindow {
    init(width: CGFloat, height: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask:   [.borderless, .fullSizeContentView],
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
