import SwiftUI

struct DisplayPingPoint {
    let timestamp: Date
    let latencyMs: Double
    let isLoss: Bool
}

struct DisplaySeriesPoint {
    let timestamp: Date
    let value: Double
}

func clipPointsToWindow(_ points: [DisplayPingPoint],
                        now: Date,
                        windowSeconds: TimeInterval) -> [DisplayPingPoint] {
    let clipped = clipSeriesPoints(points.map { DisplaySeriesPoint(timestamp: $0.timestamp, value: $0.latencyMs) },
                                   now: now,
                                   windowSeconds: windowSeconds)
    return clipped.map { point in
        let nearest = points.min {
            abs($0.timestamp.timeIntervalSince(point.timestamp)) < abs($1.timestamp.timeIntervalSince(point.timestamp))
        }
        return DisplayPingPoint(timestamp: point.timestamp,
                                latencyMs: point.value,
                                isLoss: nearest?.isLoss ?? false)
    }
}

func clipPointsToWindow(_ points: [DisplaySeriesPoint],
                        now: Date,
                        windowSeconds: TimeInterval) -> [DisplaySeriesPoint] {
    clipSeriesPoints(points, now: now, windowSeconds: windowSeconds)
}

private func clipSeriesPoints(_ points: [DisplaySeriesPoint],
                              now: Date,
                              windowSeconds: TimeInterval) -> [DisplaySeriesPoint] {
    guard !points.isEmpty else { return [] }
    let boundary = now.addingTimeInterval(-windowSeconds)
    let sorted = points.sorted { $0.timestamp < $1.timestamp }
    var clipped = sorted.filter { $0.timestamp >= boundary && $0.timestamp <= now }

    // Pin the first visible value to the left boundary so the graph starts
    // at the current value immediately instead of visually ramping in.
    if let firstInside = clipped.first, firstInside.timestamp > boundary {
        clipped.insert(DisplaySeriesPoint(timestamp: boundary, value: firstInside.value), at: 0)
    }

    return clipped
}

// Shared latency → color mapping used by graph, badge and dot
func latencyColor(_ ms: Double) -> Color {
    if ms < 50  { return Color(red: 0.25, green: 0.92, blue: 0.55) }
    if ms < 100 { return Color(red: 1.0,  green: 0.78, blue: 0.18) }
    return Color(red: 1.0, green: 0.35, blue: 0.35)
}

func bytesInColor() -> Color {
    Color(red: 0.30, green: 0.82, blue: 1.00)
}

func bytesOutColor() -> Color {
    Color(red: 0.16, green: 0.62, blue: 0.98)
}

// ---------------------------------------------------------------------------
// Main graph container
// ---------------------------------------------------------------------------
struct LatencyGraphView: View {
    @EnvironmentObject var store: PingStore
    private let graphWindowSeconds: TimeInterval = 60
    private var displayLagSeconds: TimeInterval { max(store.pingInterval, 0.2) }
    @State private var displayedRange = Range(min: 0, max: 120)
    @State private var displayedBytesRange = Range(min: 0, max: 4_096)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            GeometryReader { geo in
                let sz    = geo.size
                let displayNow = timeline.date.addingTimeInterval(-displayLagSeconds)
                let targetRange = dynamicLatencyRange(now: displayNow)
                let targetBytesRange = dynamicBytesRange(now: displayNow)
                let range = displayedRange
                let bytesRange = displayedBytesRange
                let showLatency = store.showLatencyGraph
                let showTraffic = store.showTrafficGraph
                let graphSize = sz

                ZStack(alignment: .topLeading) {
                    if showTraffic, let eng = primaryEngine {
                        let inPoints = displaySeriesPoints(from: eng.results, now: displayNow, value: \.bytesIn)
                        let outPoints = displaySeriesPoints(from: eng.results, now: displayNow, value: \.bytesOut)

                        ByteMidline(size: graphSize)
                        ByteAreaShape(points: inPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      color: bytesInColor(),
                                      direction: .up)
                        ByteAreaShape(points: outPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      color: bytesOutColor(),
                                      direction: .down)
                        ByteLineShape(points: inPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      color: bytesInColor().opacity(0.88),
                                      direction: .up)
                        ByteLineShape(points: outPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      color: bytesOutColor().opacity(0.78),
                                      direction: .down)
                    }

                    if showLatency {
                        ForEach(store.endpoints, id: \.id) { ep in
                            if let eng = store.engines[ep.id] {
                                let points = displayLatencyPoints(from: eng.results, now: displayNow)
                                AreaShape(results: eng.results,
                                          points: points,
                                          size: graphSize,
                                          minMs: range.min,
                                          maxMs: range.max,
                                          now: displayNow,
                                          windowSeconds: graphWindowSeconds)
                                LineShape(results: eng.results,
                                          points: points,
                                          size: graphSize,
                                          minMs: range.min,
                                          maxMs: range.max,
                                          now: displayNow,
                                          windowSeconds: graphWindowSeconds)
                            }
                        }
                    }

                    if showLatency {
                        ForEach(store.endpoints, id: \.id) { ep in
                            if let eng = store.engines[ep.id],
                               let latest = displayLatencyPoints(from: eng.results, now: displayNow).last {
                                LiveDot(color: latest.isLoss
                                    ? Color(red: 1.0, green: 0.35, blue: 0.35)
                                    : latencyColor(latest.latencyMs))
                                    .position(
                                        x: xPos(for: latest.timestamp, now: latest.timestamp, width: graphSize.width),
                                        y: yFrac(latest.latencyMs, range) * sz.height
                                    )
                            }
                        }
                    }

                    if showLatency {
                        YLabels(size: graphSize, minMs: range.min, maxMs: range.max)
                    }
                    if showTraffic {
                        YLabelsRight(size: sz, maxVal: bytesRange.max)
                    }
                }
                .onAppear {
                    displayedRange = targetRange
                    displayedBytesRange = targetBytesRange
                }
                .onChange(of: targetRange) { _, newRange in
                    withAnimation(.easeInOut(duration: max(store.pingInterval * 0.55, 0.20))) {
                        displayedRange = newRange
                    }
                }
                .onChange(of: targetBytesRange) { _, newRange in
                    withAnimation(.easeInOut(duration: max(store.pingInterval * 0.55, 0.20))) {
                        displayedBytesRange = newRange
                    }
                }
            }
        }
    }

    struct Range: Equatable { var min: Double; var max: Double }

    private var primaryEngine: PingEngine? {
        guard let id = store.endpoints.first?.id else { return nil }
        return store.engines[id]
    }

    func dynamicLatencyRange(now: Date) -> Range {
        let all = store.endpoints.flatMap {
            store.engines[$0.id]?.results.compactMap { result -> Double? in
                let ms = result.latencyMs ?? 0
                let age = now.timeIntervalSince(result.timestamp)
                guard age >= 0, age <= graphWindowSeconds else { return nil }
                return ms
            } ?? []
        }
        guard !all.isEmpty else { return Range(min: 0, max: 120) }
        let lo = max(0, all.min()! - 2.0)
        let hi = all.max()! + 2.0
        var snappedMin = floor(lo / 10) * 10
        var snappedMax = ceil(hi / 10) * 10
        if snappedMax - snappedMin < 20 {
            let mid = (lo + hi) * 0.5
            snappedMin = floor((mid - 10) / 10) * 10
            snappedMax = ceil((mid + 10) / 10) * 10
        }
        return Range(min: max(0, snappedMin), max: max(10, snappedMax))
    }

    func dynamicBytesRange(now: Date) -> Range {
        let all = primaryEngine?.results.compactMap { result -> Double? in
            let age = now.timeIntervalSince(result.timestamp)
            guard age >= 0, age <= graphWindowSeconds else { return nil }
            return max(result.bytesIn, result.bytesOut)
        } ?? []
        guard !all.isEmpty else { return Range(min: 0, max: 4_096) }
        let peak = max(all.max()! * 1.10, 512)
        return Range(min: 0, max: peak)
    }

    func yFrac(_ ms: Double, _ r: Range) -> CGFloat {
        CGFloat(1 - (min(max(ms, r.min), r.max) - r.min) / (r.max - r.min))
    }

    func xPos(for timestamp: Date, now: Date, width: CGFloat) -> CGFloat {
        let age = now.timeIntervalSince(timestamp)
        let frac = max(0, min(1, 1 - age / graphWindowSeconds))
        return width * CGFloat(frac)
    }

    // Smoothly reveals the newest segment over one sample interval instead of
    // popping the whole segment in on a single frame.
    func displayLatencyPoints(from results: [PingResult], now: Date) -> [DisplayPingPoint] {
        let vals = results.compactMap { result -> DisplayPingPoint? in
            let age = now.timeIntervalSince(result.timestamp)
            guard age >= 0 else { return nil }
            return DisplayPingPoint(timestamp: result.timestamp,
                                    latencyMs: result.latencyMs ?? 0,
                                    isLoss: result.latencyMs == nil)
        }
        guard vals.count >= 2 else { return vals }

        var displayed = vals
        let lastIdx = displayed.count - 1
        let prev = displayed[lastIdx - 1]
        let next = displayed[lastIdx]

        let sampleDuration = max(store.pingInterval,
                                 next.timestamp.timeIntervalSince(prev.timestamp),
                                 0.2)
        let reveal = max(0, min(1, now.timeIntervalSince(next.timestamp) / sampleDuration))
        if reveal < 1 {
            let t = prev.timestamp.addingTimeInterval(
                next.timestamp.timeIntervalSince(prev.timestamp) * reveal
            )
            let ms = prev.latencyMs + (next.latencyMs - prev.latencyMs) * reveal
            displayed[lastIdx] = DisplayPingPoint(timestamp: t,
                                                  latencyMs: ms,
                                                  isLoss: next.isLoss)
        }
        return displayed
    }

    func displaySeriesPoints(from results: [PingResult],
                             now: Date,
                             value: KeyPath<PingResult, Double>) -> [DisplaySeriesPoint] {
        let vals = results.compactMap { result -> DisplaySeriesPoint? in
            let age = now.timeIntervalSince(result.timestamp)
            guard age >= 0 else { return nil }
            return DisplaySeriesPoint(timestamp: result.timestamp, value: result[keyPath: value])
        }
        guard vals.count >= 2 else { return vals }

        var displayed = vals
        let lastIdx = displayed.count - 1
        let prev = displayed[lastIdx - 1]
        let next = displayed[lastIdx]

        let sampleDuration = max(store.pingInterval,
                                 next.timestamp.timeIntervalSince(prev.timestamp),
                                 0.2)
        let reveal = max(0, min(1, now.timeIntervalSince(next.timestamp) / sampleDuration))
        if reveal < 1 {
            let t = prev.timestamp.addingTimeInterval(
                next.timestamp.timeIntervalSince(prev.timestamp) * reveal
            )
            let v = prev.value + (next.value - prev.value) * reveal
            displayed[lastIdx] = DisplaySeriesPoint(timestamp: t, value: v)
        }
        return displayed
    }
}

// ---------------------------------------------------------------------------
// Grid lines
// ---------------------------------------------------------------------------
struct GridLines: View {
    let size: CGSize; let minMs: Double; let maxMs: Double

    var body: some View {
        let lines = tensValues().filter { $0 > minMs && $0 < maxMs }
        return ZStack {
            ForEach(lines, id: \.self) { ms in
                let y = CGFloat(1 - (ms - minMs) / (maxMs - minMs)) * size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.white.opacity(0.07),
                        style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
            }
        }
    }

    func tensValues() -> [Double] {
        let first = ceil(minMs / 10) * 10
        return Array(stride(from: first, through: maxMs, by: 10))
    }
}

// ---------------------------------------------------------------------------
// Y-axis labels
// ---------------------------------------------------------------------------
struct YLabels: View {
    let size: CGSize; let minMs: Double; let maxMs: Double

    var body: some View {
        let lines = displayValues()
        let topValue = lines.max()
        let bottomValue = lines.min()
        return ZStack(alignment: .topLeading) {
            ForEach(lines, id: \.self) { ms in
                let y = CGFloat(1 - (ms - minMs) / (maxMs - minMs)) * size.height
                let isTop = ms == topValue
                let isBottom = ms == bottomValue
                Text("\(Int(ms))")
                    .font(.system(size: 7.5,
                                  weight: isTop ? .semibold : .medium,
                                  design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isTop ? 0.45 : 0.28))
                    .offset(x: 3, y: isTop ? -2 : (isBottom ? size.height - 16 : y - 9))
            }
        }
    }

    func displayValues() -> [Double] {
        let bottom = floor(minMs / 10) * 10
        let top = ceil(maxMs / 10) * 10
        guard top > bottom else { return [bottom] }

        if size.height < 90 {
            return [top, bottom]
        }

        let totalTenSteps = Int((top - bottom) / 10)
        let stepMultiplier = max(1, Int(ceil(Double(totalTenSteps) / 4.0)))
        let step = Double(stepMultiplier * 10)

        var values = Array(stride(from: bottom, through: top, by: step))
        if values.last != top {
            values.append(top)
        }
        return values
    }
}

// ---------------------------------------------------------------------------
// Right Y-axis labels (bytes in/out)
// ---------------------------------------------------------------------------
struct YLabelsRight: View {
    let size: CGSize
    let maxVal: Double

    var body: some View {
        let roundedMax = roundedTenValue(maxVal)
        let half = roundedMax / 2
        let showMidLabels = size.height >= 96
        return ZStack(alignment: .topTrailing) {
            Text(formatBytesLabel(roundedMax))
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(bytesInColor().opacity(0.46))
                .offset(x: -2, y: -2)

            if showMidLabels {
                Text(formatBytesLabel(half))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(bytesInColor().opacity(0.36))
                    .offset(x: -2, y: (size.height * 0.25) - 9)
            }

            Text("0")
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.26))
                .offset(x: -2, y: (size.height / 2) - 9)

            if showMidLabels {
                Text(formatBytesLabel(half))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(bytesOutColor().opacity(0.34))
                    .offset(x: -2, y: (size.height * 0.75) - 9)
            }

            Text(formatBytesLabel(roundedMax))
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(bytesOutColor().opacity(0.40))
                .offset(x: -2, y: size.height - 16)
        }
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
    }

    func roundedTenValue(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        if value < 10 { return 10 }
        let magnitude = pow(10, floor(log10(value)))
        let step = magnitude / 10
        return ceil(value / step) * step
    }

    func formatBytesLabel(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.0fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return "\(Int(value))B"
    }
}

// ---------------------------------------------------------------------------
// Area fill — tinted by the latest latency value
// ---------------------------------------------------------------------------
struct AreaShape: View {
    let results: [PingResult]
    let points:  [DisplayPingPoint]
    let size:    CGSize
    let minMs:   Double
    let maxMs:   Double
    let now:     Date
    let windowSeconds: TimeInterval

    var body: some View {
        let pts      = validPoints()
        let latestMs = pts.last?.ms ?? 20
        let color    = latencyColor(latestMs)
        guard pts.count >= 2 else { return AnyView(EmptyView()) }

        let path = Path { p in
            p.move(to: CGPoint(x: pts[0].point.x, y: size.height))
            p.addLine(to: pts[0].point)
            addSmoothSegments(&p, points: pts.map(\.point))
            p.addLine(to: CGPoint(x: pts.last!.point.x, y: size.height))
            p.closeSubpath()
        }
        return AnyView(
            path.fill(LinearGradient(
                colors: [color.opacity(0.20), color.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))
        )
    }

    struct Pt { let point: CGPoint; let ms: Double }

    func validPoints() -> [Pt] {
        let plotNow = points.last?.timestamp ?? now
        return clipPointsToWindow(points, now: plotNow, windowSeconds: windowSeconds).compactMap { point in
            let age = plotNow.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            return Pt(point: CGPoint(
                x: size.width * CGFloat(frac),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs)
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let a = points[i]
            let b = points[i + 1]
            let c1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
            let c2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
            path.addCurve(to: b, control1: c1, control2: c2)
        }
    }
}

// ---------------------------------------------------------------------------
// Line — each segment colored by the latency at that point
// ---------------------------------------------------------------------------
struct LineShape: View {
    let results: [PingResult]
    let points:  [DisplayPingPoint]
    let size:    CGSize
    let minMs:   Double
    let maxMs:   Double
    let now:     Date
    let windowSeconds: TimeInterval

    struct Pt { let point: CGPoint; let ms: Double; let isLoss: Bool }

    var body: some View {
        let pts = validPoints()
        guard pts.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            ZStack {
                ForEach(0 ..< pts.count - 1, id: \.self) { i in
                    let a = pts[i].point
                    let b = pts[i + 1].point
                    let col = (pts[i].isLoss || pts[i + 1].isLoss)
                        ? Color(red: 1.0, green: 0.35, blue: 0.35)
                        : latencyColor((pts[i].ms + pts[i + 1].ms) * 0.5)
                    let c1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
                    let c2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
                    Path { p in
                        p.move(to: a)
                        p.addCurve(to: b, control1: c1, control2: c2)
                    }
                    .stroke(col,
                            style: StrokeStyle(lineWidth: 2.1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .shadow(color: col.opacity(0.58), radius: 3.5)
                }
            }
        )
    }

    func validPoints() -> [Pt] {
        let plotNow = points.last?.timestamp ?? now
        return clipPointsToWindow(points, now: plotNow, windowSeconds: windowSeconds).compactMap { point in
            let age = plotNow.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            return Pt(point: CGPoint(
                x: size.width * CGFloat(frac),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs, isLoss: point.isLoss)
        }
    }

}

// ---------------------------------------------------------------------------
// Bytes line (drawn behind latency)
// ---------------------------------------------------------------------------
struct ByteAreaShape: View {
    enum Direction {
        case up
        case down
    }

    let points: [DisplaySeriesPoint]
    let size: CGSize
    let maxVal: Double
    let now: Date
    let windowSeconds: TimeInterval
    let color: Color
    let direction: Direction

    struct Pt { let point: CGPoint }

    var body: some View {
        let pts = validPoints()
        guard pts.count >= 2 else { return AnyView(EmptyView()) }
        let midY = size.height * 0.5

        let path = Path { p in
            p.move(to: CGPoint(x: pts[0].point.x, y: midY))
            p.addLine(to: pts[0].point)
            addSmoothSegments(&p, points: pts.map(\.point))
            p.addLine(to: CGPoint(x: pts.last!.point.x, y: midY))
            p.closeSubpath()
        }

        return AnyView(
            path.fill(LinearGradient(
                colors: direction == .up
                    ? [color.opacity(0.17), color.opacity(0.03)]
                    : [color.opacity(0.03), color.opacity(0.17)],
                startPoint: .top,
                endPoint: .bottom
            ))
        )
    }

    func validPoints() -> [Pt] {
        let plotNow = points.last?.timestamp ?? now
        return clipPointsToWindow(points, now: plotNow, windowSeconds: windowSeconds).compactMap { point in
            let age = plotNow.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            let half = size.height * 0.5
            let normalized = min(max(point.value, 0), maxVal) / max(maxVal, 1)
            let y = direction == .up
                ? half - CGFloat(normalized) * half
                : half + CGFloat(normalized) * half
            return Pt(point: CGPoint(x: size.width * CGFloat(frac), y: y))
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let a = points[i]
            let b = points[i + 1]
            let c1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
            let c2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
            path.addCurve(to: b, control1: c1, control2: c2)
        }
    }
}

// ---------------------------------------------------------------------------
// Bytes line (drawn behind latency)
// ---------------------------------------------------------------------------
struct ByteLineShape: View {
    enum Direction {
        case up
        case down
    }

    let points: [DisplaySeriesPoint]
    let size: CGSize
    let maxVal: Double
    let now: Date
    let windowSeconds: TimeInterval
    let color: Color
    let direction: Direction

    struct Pt { let point: CGPoint }

    var body: some View {
        let pts = validPoints()
        guard pts.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            Path { p in
                p.move(to: pts[0].point)
                addSmoothSegments(&p, points: pts.map(\.point))
            }
            .stroke(color,
                    style: StrokeStyle(lineWidth: 1.35,
                                       lineCap: .round,
                                       lineJoin: .round))
            .shadow(color: color.opacity(0.20), radius: 2.5)
        )
    }

    func validPoints() -> [Pt] {
        let plotNow = points.last?.timestamp ?? now
        return clipPointsToWindow(points, now: plotNow, windowSeconds: windowSeconds).compactMap { point in
            let age = plotNow.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            let half = size.height * 0.5
            let normalized = min(max(point.value, 0), maxVal) / max(maxVal, 1)
            let y = direction == .up
                ? half - CGFloat(normalized) * half
                : half + CGFloat(normalized) * half
            return Pt(point: CGPoint(
                x: size.width * CGFloat(frac),
                y: y
            ))
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let a = points[i]
            let b = points[i + 1]
            let c1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
            let c2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
            path.addCurve(to: b, control1: c1, control2: c2)
        }
    }
}

struct ByteMidline: View {
    let size: CGSize

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height * 0.5))
            p.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
        }
        .stroke(Color.white.opacity(0.11), style: StrokeStyle(lineWidth: 0.9))
    }
}

// ---------------------------------------------------------------------------
// Pulsing live dot
// ---------------------------------------------------------------------------
struct LiveDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(pulse ? 0 : 0.35))
                .frame(width: pulse ? 11 : 6, height: pulse ? 11 : 6)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .shadow(color: color.opacity(0.85), radius: 3)
        }
        .onAppear { pulse = true }
    }
}
