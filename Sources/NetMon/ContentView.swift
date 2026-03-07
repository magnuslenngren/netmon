import SwiftUI
import AppKit

// ---------------------------------------------------------------------------
// Root widget view
// ---------------------------------------------------------------------------
struct ContentView: View {
    @EnvironmentObject var store: PingStore

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {
                HeaderBar()
                    .environmentObject(store)

                if !store.isCompact {
                    LatencyGraphView()
                        .environmentObject(store)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(width: kWidgetWidth,
               height: store.isCompact ? kWidgetCompactHeight : kWidgetHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.isCompact)

    }
}

// ---------------------------------------------------------------------------
// Header bar
// ---------------------------------------------------------------------------
struct HeaderBar: View {
    @EnvironmentObject var store: PingStore

    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            PulsingDot(color: statusColor)

            // Title
            Text("NetMon")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            // Best latency badge
            if let best = bestLatency {
                Text(String(format: "%.0f ms", best))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(latencyColor(best))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(latencyColor(best).opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(latencyColor(best).opacity(0.3), lineWidth: 0.5))
            } else {
                Text("—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }


        }
        .padding(.horizontal, 10)
        .padding(.vertical, store.isCompact ? 9 : 7)
        .overlay(
            ClickHandler(
                onDoubleClick: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        store.isCompact.toggle()
                    }
                    resizeWindow(compact: store.isCompact)
                },
                onRightClick: { event in
                    let menu = NSMenu()
                    let quitItem = NSMenuItem(title: "Quit NetMon",
                                             action: #selector(NSApplication.terminate(_:)),
                                             keyEquivalent: "q")
                    quitItem.target = NSApp
                    menu.addItem(quitItem)
                    NSMenu.popUpContextMenu(menu, with: event,
                                           for: event.window?.contentView ?? NSView())
                }
            )
        )
    }

    // Animate window height while keeping top-right corner pinned
    private func resizeWindow(compact: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is GlassWindow }) else { return }
        let newH = compact ? kWidgetCompactHeight : kWidgetHeight
        var f = window.frame
        f.origin.y  = f.origin.y + f.height - newH  // keep top edge fixed
        f.size.height = newH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration       = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(f, display: true)
        }
    }

    // MARK: – Helpers
    private var bestLatency: Double? {
        store.endpoints.compactMap { store.engines[$0.id]?.results.last?.latencyMs }.min()
    }
    private var statusColor: Color {
        guard let ms = bestLatency else { return .red }
        return latencyColor(ms)
    }
    // Use shared latencyColor() from LatencyGraphView.swift
}

// ---------------------------------------------------------------------------
// Unified double-click + right-click handler
// ---------------------------------------------------------------------------
struct ClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void
    let onRightClick:  (NSEvent) -> Void

    func makeNSView(context: Context) -> ClickView {
        ClickView(onDoubleClick: onDoubleClick, onRightClick: onRightClick)
    }
    func updateNSView(_ v: ClickView, context: Context) {
        v.onDoubleClick = onDoubleClick
        v.onRightClick  = onRightClick
    }
}

class ClickView: NSView {
    var onDoubleClick: () -> Void
    var onRightClick:  (NSEvent) -> Void

    init(onDoubleClick: @escaping () -> Void, onRightClick: @escaping (NSEvent) -> Void) {
        self.onDoubleClick = onDoubleClick
        self.onRightClick  = onRightClick
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick() }
    }
    override func rightMouseDown(with event: NSEvent) {
        onRightClick(event)
    }
}

// ---------------------------------------------------------------------------
// Glass background
// ---------------------------------------------------------------------------
struct GlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBlur()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Dark tinted overlay so content is always legible
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.16).opacity(0.85),
                        Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.90),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Gloss sheen on top edge
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.5)
                ))

            // Hairline border
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }
}

// ---------------------------------------------------------------------------
// Pulsing status dot
// ---------------------------------------------------------------------------
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(pulse ? 0 : 0.3))
                .frame(width: pulse ? 12 : 6, height: pulse ? 12 : 6)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.8), radius: 3)
        }
        .onAppear { pulse = true }
    }
}

// ---------------------------------------------------------------------------
// NSVisualEffectView wrapper
// ---------------------------------------------------------------------------
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v          = NSVisualEffectView()
        v.material     = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state        = .active
        v.appearance   = NSAppearance(named: .darkAqua)
        v.wantsLayer   = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
