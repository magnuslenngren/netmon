import SwiftUI

struct ProcessTrafficView: View {
    let direction: TrafficDirection
    @StateObject private var traffic = ProcessTrafficStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(direction.title).font(.headline)
            Text("Live bandwidth · updates every second")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if let error = traffic.error {
                Text(error).foregroundStyle(.secondary)
            } else if traffic.isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Measuring bandwidth…").foregroundStyle(.secondary)
                }
            } else {
                let rows = ProcessTraffic.top(traffic.rows, direction: direction)
                if rows.isEmpty {
                    Text(direction == .down ? "No active downloads" : "No active uploads")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).lineLimit(1).truncationMode(.middle)
                            Text("PID \(row.id)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(rateText(row.rate(for: direction)))
                            .monospacedDigit().fixedSize()
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 310, alignment: .leading)
        .onAppear { traffic.start() }
        .onDisappear { traffic.stop() }
    }

    private func rateText(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1f KB/s", value / 1_000) }
        return String(format: "%.0f B/s", value)
    }
}

struct TrafficBadgeFrames: PreferenceKey {
    static var defaultValue: [TrafficDirection: CGRect] = [:]
    static func reduce(value: inout [TrafficDirection: CGRect], nextValue: () -> [TrafficDirection: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TrafficBadge: ViewModifier {
    let direction: TrafficDirection
    @Binding var selection: TrafficDirection?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.preference(key: TrafficBadgeFrames.self,
                                       value: [direction: geometry.frame(in: .named("widget"))])
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(direction.title)
            .accessibilityAction { selection = direction }
            .popover(isPresented: Binding(get: { selection == direction },
                                          set: { if !$0, selection == direction { selection = nil } }),
                     arrowEdge: .bottom) {
                ProcessTrafficView(direction: direction)
            }
    }
}
