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

    if let firstInside = clipped.first,
       let insideIdx = sorted.firstIndex(where: { $0.timestamp == firstInside.timestamp }),
       insideIdx > 0 {
        let before = sorted[insideIdx - 1]
        let after = sorted[insideIdx]
        if before.timestamp < boundary, after.timestamp > boundary {
            let span = after.timestamp.timeIntervalSince(before.timestamp)
            if span > 0 {
                let ratio = boundary.timeIntervalSince(before.timestamp) / span
                let v = before.value + (after.value - before.value) * ratio
                clipped.insert(DisplaySeriesPoint(timestamp: boundary, value: v), at: 0)
            }
        }
    }

    if clipped.last?.timestamp != now,
       let before = sorted.last(where: { $0.timestamp <= now }),
       let beforeIdx = sorted.firstIndex(where: { $0.timestamp == before.timestamp }),
       (beforeIdx + 1) < sorted.count {
        let after = sorted[beforeIdx + 1]
        if after.timestamp > now {
            let span = after.timestamp.timeIntervalSince(before.timestamp)
            if span > 0 {
                let ratio = now.timeIntervalSince(before.timestamp) / span
                let v = before.value + (after.value - before.value) * ratio
                clipped.append(DisplaySeriesPoint(timestamp: now, value: v))
            }
        }
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

private func plotXPosition(timestamp: Date,
                           now: Date,
                           width: CGFloat,
                           windowSeconds: TimeInterval,
                           rightInset: CGFloat) -> CGFloat {
    let age = now.timeIntervalSince(timestamp)
    let frac = max(0, min(1, 1 - age / windowSeconds))
    let plotWidth = max(width - rightInset, 0)
    return plotWidth * CGFloat(frac)
}

private func stableSplineControls(points: [CGPoint], index: Int) -> (CGPoint, CGPoint) {
    let a = points[index]
    let b = points[index + 1]
    let prev = index > 0 ? points[index - 1] : a

    // Backward-difference tangents keep historical segments stable:
    // adding a future sample does not reshape already-drawn points.
    let tangentA = CGPoint(x: (b.x - prev.x) * 0.5, y: (b.y - prev.y) * 0.5)
    let tangentB = CGPoint(x: b.x - a.x, y: b.y - a.y)

    let c1 = CGPoint(x: a.x + tangentA.x / 3.0, y: a.y + tangentA.y / 3.0)
    let c2 = CGPoint(x: b.x - tangentB.x / 3.0, y: b.y - tangentB.y / 3.0)
    return (c1, c2)
}

private struct CubicBezierSegment {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t

        return CGPoint(
            x: (mt2 * mt * p0.x)
                + (3 * mt2 * t * p1.x)
                + (3 * mt * t2 * p2.x)
                + (t2 * t * p3.x),
            y: (mt2 * mt * p0.y)
                + (3 * mt2 * t * p1.y)
                + (3 * mt * t2 * p2.y)
                + (t2 * t * p3.y)
        )
    }

    func split(at t: CGFloat) -> (CubicBezierSegment, CubicBezierSegment) {
        let p01 = interpolate(p0, p1, t: t)
        let p12 = interpolate(p1, p2, t: t)
        let p23 = interpolate(p2, p3, t: t)
        let p012 = interpolate(p01, p12, t: t)
        let p123 = interpolate(p12, p23, t: t)
        let p0123 = interpolate(p012, p123, t: t)

        return (
            CubicBezierSegment(p0: p0, p1: p01, p2: p012, p3: p0123),
            CubicBezierSegment(p0: p0123, p1: p123, p2: p23, p3: p3)
        )
    }

    func trimmed(from start: CGFloat, to end: CGFloat) -> CubicBezierSegment {
        if start <= 0, end >= 1 { return self }

        let clampedStart = max(0, min(1, start))
        let clampedEnd = max(clampedStart, min(1, end))
        let (head, _) = split(at: clampedEnd)

        guard clampedEnd > clampedStart else { return head }
        if clampedStart <= 0 { return head }

        let normalizedStart = clampedStart / clampedEnd
        let (_, trimmed) = head.split(at: normalizedStart)
        return trimmed
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t,
                y: a.y + (b.y - a.y) * t)
    }
}

// ---------------------------------------------------------------------------
// Main graph container
// ---------------------------------------------------------------------------
struct LatencyGraphView: View {
    @EnvironmentObject var store: PingStore
    private let graphWindowSeconds: TimeInterval = 60
    private let graphRightInset: CGFloat = 4
    private var displayLagSeconds: TimeInterval {
        let fallback = max(store.pingInterval, 0.2)
        guard let results = primaryEngine?.results, results.count >= 2 else { return fallback }
        let last = results[results.count - 1].timestamp
        let prev = results[results.count - 2].timestamp
        let actualGap = last.timeIntervalSince(prev)
        return max(min(actualGap, fallback * 1.5), 0.2)
    }
    @State private var displayedRange = Range(min: 0, max: 120)
    @State private var displayedBytesRange = Range(min: 0, max: 4_096)
    @State private var lastScaleUpdateAt: Date?

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
                                      rightInset: graphRightInset,
                                      color: bytesInColor(),
                                      direction: .up)
                        ByteAreaShape(points: outPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      rightInset: graphRightInset,
                                      color: bytesOutColor(),
                                      direction: .down)
                        ByteLineShape(points: inPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      rightInset: graphRightInset,
                                      color: bytesInColor().opacity(0.88),
                                      direction: .up)
                        ByteLineShape(points: outPoints,
                                      size: graphSize,
                                      maxVal: bytesRange.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds,
                                      rightInset: graphRightInset,
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
                                          windowSeconds: graphWindowSeconds,
                                          rightInset: graphRightInset)
                                LineShape(results: eng.results,
                                          points: points,
                                          size: graphSize,
                                          minMs: range.min,
                                          maxMs: range.max,
                                          now: displayNow,
                                          windowSeconds: graphWindowSeconds,
                                          rightInset: graphRightInset)
                            }
                        }
                    }

                    if showLatency {
                        ForEach(store.endpoints, id: \.id) { ep in
                            if let eng = store.engines[ep.id] {
                                let rawPoints = displayLatencyPoints(from: eng.results, now: displayNow)
                                let visiblePoints = clipPointsToWindow(rawPoints,
                                                                       now: displayNow,
                                                                       windowSeconds: graphWindowSeconds)
                                if visiblePoints.count >= 2, let latest = visiblePoints.last {
                                LiveDot(color: latest.isLoss
                                    ? Color(red: 1.0, green: 0.35, blue: 0.35)
                                    : latencyColor(latest.latencyMs))
                                    .position(
                                        x: plotXPosition(timestamp: latest.timestamp,
                                                         now: displayNow,
                                                         width: graphSize.width,
                                                         windowSeconds: graphWindowSeconds,
                                                         rightInset: graphRightInset),
                                        y: yFrac(latest.latencyMs, range) * sz.height
                                    )
                                }
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
                    lastScaleUpdateAt = timeline.date
                }
                .onChange(of: timeline.date) { _, now in
                    advanceDisplayedRanges(at: now,
                                           latencyTarget: targetRange,
                                           bytesTarget: targetBytesRange)
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

    func displayLatencyPoints(from results: [PingResult], now: Date) -> [DisplayPingPoint] {
        results.map { result in
            DisplayPingPoint(timestamp: result.timestamp,
                             latencyMs: result.latencyMs ?? 0,
                             isLoss: result.latencyMs == nil)
        }
    }

    func displaySeriesPoints(from results: [PingResult],
                             now: Date,
                             value: KeyPath<PingResult, Double>) -> [DisplaySeriesPoint] {
        results.map { result in
            DisplaySeriesPoint(timestamp: result.timestamp, value: result[keyPath: value])
        }
    }

    private func advanceDisplayedRanges(at now: Date,
                                        latencyTarget: Range,
                                        bytesTarget: Range) {
        guard let lastUpdate = lastScaleUpdateAt else {
            displayedRange = latencyTarget
            displayedBytesRange = bytesTarget
            lastScaleUpdateAt = now
            return
        }

        lastScaleUpdateAt = now
        let deltaTime = max(now.timeIntervalSince(lastUpdate), 0)
        guard deltaTime > 0 else { return }

        let nextLatencyRange = easedRange(from: displayedRange,
                                          to: latencyTarget,
                                          deltaTime: deltaTime,
                                          response: max(store.pingInterval * 0.9, 0.35),
                                          tolerance: 0.05)
        let nextBytesRange = easedRange(from: displayedBytesRange,
                                        to: bytesTarget,
                                        deltaTime: deltaTime,
                                        response: max(store.pingInterval * 1.1, 0.45),
                                        tolerance: max(bytesTarget.max * 0.003, 1))

        if nextLatencyRange != displayedRange {
            displayedRange = nextLatencyRange
        }
        if nextBytesRange != displayedBytesRange {
            displayedBytesRange = nextBytesRange
        }
    }

    private func easedRange(from current: Range,
                            to target: Range,
                            deltaTime: TimeInterval,
                            response: TimeInterval,
                            tolerance: Double) -> Range {
        let blend = smoothingBlend(deltaTime: deltaTime, response: response)
        let nextMin = interpolatedValue(current.min, target.min, blend: blend, tolerance: tolerance)
        let nextMax = interpolatedValue(current.max, target.max, blend: blend, tolerance: tolerance)
        return normalizedRange(minValue: nextMin, maxValue: nextMax, fallback: target)
    }

    private func smoothingBlend(deltaTime: TimeInterval, response: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }
        return 1 - exp(-deltaTime / max(response, 0.001))
    }

    private func interpolatedValue(_ current: Double,
                                   _ target: Double,
                                   blend: Double,
                                   tolerance: Double) -> Double {
        let next = current + (target - current) * blend
        return abs(next - target) <= tolerance ? target : next
    }

    private func normalizedRange(minValue: Double,
                                 maxValue: Double,
                                 fallback: Range) -> Range {
        let safeMax = Swift.max(maxValue, minValue + 1)
        let normalized = Range(min: minValue, max: safeMax)
        return normalized.max.isFinite && normalized.min.isFinite ? normalized : fallback
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
    let rightInset: CGFloat

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
        return clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            return Pt(point: CGPoint(
                x: plotXPosition(timestamp: point.timestamp,
                                 now: now,
                                 width: size.width,
                                 windowSeconds: windowSeconds,
                                 rightInset: rightInset),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs)
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let b = points[i + 1]
            let (c1, c2) = stableSplineControls(points: points, index: i)
            path.addCurve(to: b, control1: c1, control2: c2)
        }
    }
}

// ---------------------------------------------------------------------------
// Line — split rendered spline segments at threshold crossings so brief spikes
// can show green/yellow/red transitions within one peak.
// ---------------------------------------------------------------------------
struct LineShape: View {
    let results: [PingResult]
    let points:  [DisplayPingPoint]
    let size:    CGSize
    let minMs:   Double
    let maxMs:   Double
    let now:     Date
    let windowSeconds: TimeInterval
    let rightInset: CGFloat

    struct Pt { let point: CGPoint; let ms: Double; let isLoss: Bool }
    private struct ColoredSegment { let curve: CubicBezierSegment; let color: Color }

    var body: some View {
        let pts = validPoints()
        guard pts.count >= 2 else { return AnyView(EmptyView()) }
        let curvePoints = pts.map(\.point)
        let coloredSegments = coloredSegments(points: pts, curvePoints: curvePoints)

        return AnyView(
            ZStack {
                ForEach(0 ..< coloredSegments.count, id: \.self) { i in
                    let segment = coloredSegments[i]
                    Path { p in
                        p.move(to: segment.curve.p0)
                        p.addCurve(to: segment.curve.p3,
                                   control1: segment.curve.p1,
                                   control2: segment.curve.p2)
                    }
                    .stroke(segment.color,
                            style: StrokeStyle(lineWidth: 2.1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .shadow(color: segment.color.opacity(0.58), radius: 3.5)
                }
            }
        )
    }

    func validPoints() -> [Pt] {
        return clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            return Pt(point: CGPoint(
                x: plotXPosition(timestamp: point.timestamp,
                                 now: now,
                                 width: size.width,
                                 windowSeconds: windowSeconds,
                                 rightInset: rightInset),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs, isLoss: point.isLoss)
        }
    }

    private func coloredSegments(points: [Pt], curvePoints: [CGPoint]) -> [ColoredSegment] {
        var segments: [ColoredSegment] = []

        for i in 0 ..< points.count - 1 {
            let start = points[i]
            let end = points[i + 1]
            let (c1, c2) = stableSplineControls(points: curvePoints, index: i)
            let curve = CubicBezierSegment(p0: start.point, p1: c1, p2: c2, p3: end.point)

            if start.isLoss || end.isLoss {
                segments.append(ColoredSegment(curve: curve,
                                               color: Color(red: 1.0, green: 0.35, blue: 0.35)))
                continue
            }

            let breakpoints = thresholdBreakpoints(for: curve)
            for index in 0 ..< breakpoints.count - 1 {
                let startT = breakpoints[index]
                let endT = breakpoints[index + 1]
                guard endT - startT > 0.0001 else { continue }

                let midpoint = curve.point(at: (startT + endT) * 0.5)
                let ms = latencyMs(forY: midpoint.y)
                segments.append(ColoredSegment(curve: curve.trimmed(from: startT, to: endT),
                                               color: latencyColor(ms)))
            }
        }

        return segments
    }

    private func thresholdBreakpoints(for curve: CubicBezierSegment) -> [CGFloat] {
        let thresholds = [50.0, 100.0]
        let values = ([CGFloat(0), CGFloat(1)] + thresholds.flatMap { thresholdCrossings(for: curve, thresholdMs: $0) })
            .sorted()

        var unique: [CGFloat] = []
        for value in values {
            if let last = unique.last, abs(last - value) < 0.0005 { continue }
            unique.append(value)
        }
        return unique
    }

    private func thresholdCrossings(for curve: CubicBezierSegment, thresholdMs: Double) -> [CGFloat] {
        guard thresholdMs > minMs, thresholdMs < maxMs else { return [] }

        let targetY = yPosition(for: thresholdMs)
        let sampleCount = 32
        let epsilon: CGFloat = 0.0001
        var crossings: [CGFloat] = []
        var previousT: CGFloat = 0
        var previousValue = curve.point(at: previousT).y - targetY

        for sample in 1 ... sampleCount {
            let t = CGFloat(sample) / CGFloat(sampleCount)
            let value = curve.point(at: t).y - targetY

            if abs(value) < epsilon {
                crossings.append(t)
            }

            if (previousValue < 0 && value > 0) || (previousValue > 0 && value < 0) {
                crossings.append(refineCrossing(for: curve,
                                                targetY: targetY,
                                                lowT: previousT,
                                                highT: t))
            }

            previousT = t
            previousValue = value
        }

        return crossings
    }

    private func refineCrossing(for curve: CubicBezierSegment,
                                targetY: CGFloat,
                                lowT: CGFloat,
                                highT: CGFloat) -> CGFloat {
        var lower = lowT
        var upper = highT
        var lowerValue = curve.point(at: lower).y - targetY

        for _ in 0 ..< 14 {
            let midpoint = (lower + upper) * 0.5
            let value = curve.point(at: midpoint).y - targetY

            if abs(value) < 0.0001 {
                return midpoint
            }

            if (lowerValue < 0 && value > 0) || (lowerValue > 0 && value < 0) {
                upper = midpoint
            } else {
                lower = midpoint
                lowerValue = value
            }
        }

        return (lower + upper) * 0.5
    }

    private func yPosition(for ms: Double) -> CGFloat {
        let clamped = min(max(ms, minMs), maxMs)
        let range = max(maxMs - minMs, 0.0001)
        return CGFloat(1 - (clamped - minMs) / range) * size.height
    }

    private func latencyMs(forY y: CGFloat) -> Double {
        let range = max(maxMs - minMs, 0.0001)
        let normalized = min(max(1 - (y / max(size.height, 0.0001)), 0), 1)
        return minMs + Double(normalized) * range
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
    let rightInset: CGFloat
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
        return clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let half = size.height * 0.5
            let normalized = min(max(point.value, 0), maxVal) / max(maxVal, 1)
            let y = direction == .up
                ? half - CGFloat(normalized) * half
                : half + CGFloat(normalized) * half
            return Pt(point: CGPoint(
                x: plotXPosition(timestamp: point.timestamp,
                                 now: now,
                                 width: size.width,
                                 windowSeconds: windowSeconds,
                                 rightInset: rightInset),
                y: y
            ))
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let b = points[i + 1]
            let (c1, c2) = stableSplineControls(points: points, index: i)
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
    let rightInset: CGFloat
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
        return clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let half = size.height * 0.5
            let normalized = min(max(point.value, 0), maxVal) / max(maxVal, 1)
            let y = direction == .up
                ? half - CGFloat(normalized) * half
                : half + CGFloat(normalized) * half
            return Pt(point: CGPoint(
                x: plotXPosition(timestamp: point.timestamp,
                                 now: now,
                                 width: size.width,
                                 windowSeconds: windowSeconds,
                                 rightInset: rightInset),
                y: y
            ))
        }
    }

    private func addSmoothSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        for i in 0 ..< points.count - 1 {
            let b = points[i + 1]
            let (c1, c2) = stableSplineControls(points: points, index: i)
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
