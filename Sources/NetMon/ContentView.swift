import SwiftUI
import AppKit

// ---------------------------------------------------------------------------
// Root widget view
// ---------------------------------------------------------------------------
struct ContentView: View {
    @EnvironmentObject var store: PingStore
    @AppStorage("netmon.lastExpandedHeight") private var lastExpandedHeight: Double = kWidgetHeight
    @AppStorage("netmon.isExpandedWindow") private var isExpandedWindow: Bool = false
    @AppStorage("netmon.preExpandFrame") private var preExpandFrame: String = ""

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {
                HeaderBar()
                    .environmentObject(store)

                if !store.isCompact {
                    LatencyGraphView()
                        .environmentObject(store)
                        .padding(.leading, 8)
                        .padding(.trailing, 2)
                        .padding(.bottom, 7)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.isCompact)
        .onAppear { updateWindowTitle() }
        .onChange(of: store.endpoints) { _, _ in updateWindowTitle() }
        .onReceive(NotificationCenter.default.publisher(for: .netMonToggleExpand)) { _ in
            toggleExpandOrRestore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .netMonMinimize)) { _ in
            toggleCompactMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .netMonResetView)) { _ in
            resetViewToDefault()
        }
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
                    let target = ContextMenuActionTarget.shared
                    target.onToggleLatency = { store.showLatencyGraph.toggle() }
                    target.onToggleTraffic = { store.showTrafficGraph.toggle() }
                    target.onToggleAlwaysOnTop = { store.alwaysOnTop.toggle() }
                    target.onToggleExpand = { toggleExpandOrRestore() }
                    target.onMinimize = { toggleCompactMode() }

                    // View options section
                    let alwaysOnTopItem = NSMenuItem(title: "Always on Top",
                                                     action: #selector(ContextMenuActionTarget.handleToggleAlwaysOnTop(_:)),
                                                     keyEquivalent: "")
                    alwaysOnTopItem.target = target
                    alwaysOnTopItem.state = store.alwaysOnTop ? .on : .off
                    menu.addItem(alwaysOnTopItem)

                    let minimizeItem = NSMenuItem(title: store.isCompact ? "Full" : "Minimize",
                                                  action: #selector(ContextMenuActionTarget.handleMinimize(_:)),
                                                  keyEquivalent: "m")
                    minimizeItem.target = target
                    minimizeItem.keyEquivalentModifierMask = [.command]
                    menu.addItem(minimizeItem)

                    if !store.isCompact {
                        let expandItem = NSMenuItem(title: isExpandedWindow ? "Restore Size" : "Expand",
                                                    action: #selector(ContextMenuActionTarget.handleToggleExpand(_:)),
                                                    keyEquivalent: "e")
                        expandItem.target = target
                        expandItem.keyEquivalentModifierMask = [.command]
                        menu.addItem(expandItem)
                    }

                    if let window = event.window {
                        target.onReset = {
                            resetViewToDefault(window: window)
                        }
                        let resetItem = NSMenuItem(title: "Reset View",
                                                   action: #selector(ContextMenuActionTarget.handleReset(_:)),
                                                   keyEquivalent: "r")
                        resetItem.target = target
                        resetItem.keyEquivalentModifierMask = [.command]
                        menu.addItem(resetItem)
                    }
                    menu.addItem(NSMenuItem.separator())

                    // Graph options section
                    let latencyItem = NSMenuItem(title: "Show Latency Graph",
                                                 action: #selector(ContextMenuActionTarget.handleToggleLatency(_:)),
                                                 keyEquivalent: "")
                    latencyItem.target = target
                    latencyItem.state = store.showLatencyGraph ? .on : .off
                    menu.addItem(latencyItem)

                    let trafficItem = NSMenuItem(title: "Show Traffic Graph",
                                                 action: #selector(ContextMenuActionTarget.handleToggleTraffic(_:)),
                                                 keyEquivalent: "")
                    trafficItem.target = target
                    trafficItem.state = store.showTrafficGraph ? .on : .off
                    menu.addItem(trafficItem)
                    menu.addItem(NSMenuItem.separator())

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

    private func updateWindowTitle() {
        guard let window = NSApp.windows.first(where: { $0 is GlassWindow }) else { return }
        window.title = store.endpoints.first?.host ?? "NetMon"
    }

    // Animate window height while keeping top-right corner pinned
    private func resizeWindow(compact: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is GlassWindow }) else { return }
        if compact, window.frame.height > kWidgetCompactHeight {
            lastExpandedHeight = window.frame.height
        }

        if compact {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }

        window.minSize = NSSize(width: kWidgetWidth,
                                height: compact ? kWidgetCompactHeight : kWidgetHeight)
        window.maxSize = NSSize(width: .greatestFiniteMagnitude,
                                height: compact ? kWidgetCompactHeight : .greatestFiniteMagnitude)

        let newH = compact ? kWidgetCompactHeight : max(CGFloat(lastExpandedHeight), kWidgetHeight)
        var f = window.frame
        f.origin.y = f.origin.y + f.height - newH // keep top edge fixed
        f.size.height = newH
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(f, display: true)
        }
    }

    private func toggleCompactMode() {
        if store.isCompact {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.isCompact = false
            }
            resizeWindow(compact: false)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.isCompact = true
            }
            resizeWindow(compact: true)
        }
    }

    private func toggleExpandOrRestore() {
        guard !store.isCompact else { return }
        guard let window = NSApp.windows.first(where: { $0 is GlassWindow }) else { return }

        if isExpandedWindow, !preExpandFrame.isEmpty {
            let frame = NSRectFromString(preExpandFrame)
            if frame.width > 0, frame.height > 0 {
                window.setFrame(frame, display: true, animate: true)
            }
            isExpandedWindow = false
            preExpandFrame = ""
            return
        }

        preExpandFrame = NSStringFromRect(window.frame)
        let current = window.frame
        let visible = primaryVisibleFrame()
        var target = current
        target.size = NSSize(width: current.width * 4, height: current.height * 4)

        if target.width <= visible.width, target.height <= visible.height {
            let right = current.maxX
            let top = current.maxY
            target.origin.x = right - target.width
            target.origin.y = top - target.height
            target.origin.x = max(visible.minX, min(target.origin.x, visible.maxX - target.width))
            target.origin.y = max(visible.minY, min(target.origin.y, visible.maxY - target.height))
        } else {
            target = visible
        }

        window.setFrame(target, display: true, animate: true)
        isExpandedWindow = true
    }

    private func resetViewToDefault(window: NSWindow? = nil) {
        guard let targetWindow = window ?? NSApp.windows.first(where: { $0 is GlassWindow }) else { return }
        resetNetMonWindowView(window: targetWindow, isCompact: store.isCompact)
        lastExpandedHeight = kWidgetHeight
        isExpandedWindow = false
        preExpandFrame = ""
    }
}

// ---------------------------------------------------------------------------
// Header bar
// ---------------------------------------------------------------------------
struct HeaderBar: View {
    @EnvironmentObject var store: PingStore

    var body: some View {
        GeometryReader { geo in
            let style = headerStyle(for: geo.size.width, compact: store.isCompact)
            HStack(spacing: 0) {
                metricBox(label: latencyLabel(for: style.labelMode),
                          value: latencyValueText,
                          color: latencyBoxColor,
                          style: style)

                Spacer(minLength: style.showCenterTitle ? 8 : 2)

                if style.showCenterTitle {
                    Text("NetMon")
                        .font(.system(size: compactTitleFontSize(for: style), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }

                HStack(spacing: style.spacing) {
                    metricBox(label: bytesDownLabel(for: style.labelMode),
                              value: bytesDownText,
                              color: bytesInColor(),
                              style: style)
                    metricBox(label: bytesUpLabel(for: style.labelMode),
                              value: bytesUpText,
                              color: bytesOutColor(),
                              style: style)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: store.isCompact ? 17 : 18)
        .padding(.horizontal, store.isCompact ? 6 : 10)
        .padding(.vertical, store.isCompact ? 1 : 7)
    }

    // MARK: – Helpers
    private var latestResult: PingResult? {
        guard let id = store.endpoints.first?.id else { return nil }
        return store.engines[id]?.results.last
    }

    private var latencyValueText: String {
        guard let ms = latestResult?.latencyMs else { return "—" }
        return String(format: "%.0fms", ms)
    }

    private var bytesDownText: String {
        guard let bytes = latestResult?.bytesIn else { return "—" }
        return formatBytes(bytes)
    }

    private var bytesUpText: String {
        guard let bytes = latestResult?.bytesOut else { return "—" }
        return formatBytes(bytes)
    }

    private var latencyBoxColor: Color {
        guard let ms = latestResult?.latencyMs else { return .white.opacity(0.6) }
        return latencyColor(ms)
    }

    private struct HeaderStyle {
        enum LabelMode {
            case none
            case short
            case full
        }

        let labelMode: LabelMode
        let showCenterTitle: Bool
        let labelSize: CGFloat
        let valueSize: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let spacing: CGFloat
    }

    private func headerStyle(for width: CGFloat, compact: Bool) -> HeaderStyle {
        let showCenterTitle = width >= (compact ? 500 : 520)
        let labelMode: HeaderStyle.LabelMode
        if width < (compact ? 255 : 275) {
            labelMode = .none
        } else if width < (compact ? 360 : 390) {
            labelMode = .short
        } else {
            labelMode = .full
        }

        if width < 200 {
            return HeaderStyle(labelMode: .none,
                               showCenterTitle: false,
                               labelSize: 7,
                               valueSize: compact ? 9.8 : 8.8,
                               horizontalPadding: compact ? 9 : 7,
                               verticalPadding: compact ? 2.2 : 1.5,
                               spacing: compact ? 3 : 5)
        }
        if width < 240 {
            return HeaderStyle(labelMode: .none,
                               showCenterTitle: false,
                               labelSize: 7.5,
                               valueSize: compact ? 10.4 : 9.4,
                               horizontalPadding: compact ? 10 : 8,
                               verticalPadding: compact ? 2.3 : 1.8,
                               spacing: 6)
        }
        return HeaderStyle(labelMode: labelMode,
                           showCenterTitle: showCenterTitle,
                           labelSize: 8,
                           valueSize: compact ? 10.8 : 10,
                           horizontalPadding: compact ? 9 : 7,
                           verticalPadding: compact ? 2.3 : 2,
                           spacing: 8)
    }

    private func metricBox(label: String, value: String, color: Color, style: HeaderStyle) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: style.labelSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text(value)
                .font(.system(size: style.valueSize, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.5))
    }

    private func latencyLabel(for mode: HeaderStyle.LabelMode) -> String {
        switch mode {
        case .none: return ""
        case .short: return "LAT"
        case .full: return "Latency"
        }
    }

    private func bytesDownLabel(for mode: HeaderStyle.LabelMode) -> String {
        switch mode {
        case .none: return ""
        case .short: return "DN"
        case .full: return "Bytes Down"
        }
    }

    private func bytesUpLabel(for mode: HeaderStyle.LabelMode) -> String {
        switch mode {
        case .none: return ""
        case .short: return "UP"
        case .full: return "Bytes Up"
        }
    }

    private func compactTitleFontSize(for style: HeaderStyle) -> CGFloat {
        store.isCompact ? (style.valueSize - 1.2) : (style.valueSize - 0.6)
    }

    private func formatBytes(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(Int(value))B"
    }
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

final class ContextMenuActionTarget: NSObject {
    static let shared = ContextMenuActionTarget()
    var onReset: (() -> Void)?
    var onToggleLatency: (() -> Void)?
    var onToggleTraffic: (() -> Void)?
    var onToggleAlwaysOnTop: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onMinimize: (() -> Void)?

    @objc func handleReset(_ sender: Any?) {
        onReset?()
    }

    @objc func handleToggleLatency(_ sender: Any?) {
        onToggleLatency?()
    }

    @objc func handleToggleTraffic(_ sender: Any?) {
        onToggleTraffic?()
    }

    @objc func handleToggleAlwaysOnTop(_ sender: Any?) {
        onToggleAlwaysOnTop?()
    }

    @objc func handleToggleExpand(_ sender: Any?) {
        onToggleExpand?()
    }

    @objc func handleMinimize(_ sender: Any?) {
        onMinimize?()
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
                        Color(red: 0.09, green: 0.10, blue: 0.16).opacity(0.49),
                        Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.56),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            // Gloss sheen on top edge
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.5)
                ))

            // Hairline border
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.04)],
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
