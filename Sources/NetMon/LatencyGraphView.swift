import SwiftUI

struct DisplayPingPoint {
    let timestamp: Date
    let latencyMs: Double
}

func clipPointsToWindow(_ points: [DisplayPingPoint],
                        now: Date,
                        windowSeconds: TimeInterval) -> [DisplayPingPoint] {
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
                let ms = before.latencyMs + (after.latencyMs - before.latencyMs) * ratio
                clipped.insert(DisplayPingPoint(timestamp: boundary, latencyMs: ms), at: 0)
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

// ---------------------------------------------------------------------------
// Main graph container
// ---------------------------------------------------------------------------
struct LatencyGraphView: View {
    @EnvironmentObject var store: PingStore
    private let graphWindowSeconds: TimeInterval = 60
    private var displayLagSeconds: TimeInterval { max(store.pingInterval, 0.2) }
    @State private var displayedRange = Range(min: 0, max: 120)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            GeometryReader { geo in
                let sz    = geo.size
                let displayNow = timeline.date.addingTimeInterval(-displayLagSeconds)
                let targetRange = dynamicRange(now: displayNow)
                let range = displayedRange

                ZStack(alignment: .topLeading) {
                    GridLines(size: sz, minMs: range.min, maxMs: range.max)

                    ForEach(store.endpoints, id: \.id) { ep in
                        if let eng = store.engines[ep.id] {
                            let points = displayPoints(from: eng.results, now: displayNow)
                            AreaShape(results: eng.results,
                                      points: points,
                                      size: sz,
                                      minMs: range.min,
                                      maxMs: range.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds)
                            LineShape(results: eng.results,
                                      points: points,
                                      size: sz,
                                      minMs: range.min,
                                      maxMs: range.max,
                                      now: displayNow,
                                      windowSeconds: graphWindowSeconds)
                        }
                    }

                    ForEach(store.endpoints, id: \.id) { ep in
                        if let eng = store.engines[ep.id],
                           let latest = displayPoints(from: eng.results, now: displayNow).last {
                            LiveDot(color: latencyColor(latest.latencyMs))
                                .position(
                                    x: xPos(for: latest.timestamp, now: displayNow, width: sz.width),
                                    y: yFrac(latest.latencyMs, range) * sz.height
                                )
                        }
                    }

                    YLabels(size: sz, minMs: range.min, maxMs: range.max)
                }
                .onAppear {
                    displayedRange = targetRange
                }
                .onChange(of: targetRange) { _, newRange in
                    withAnimation(.easeInOut(duration: max(store.pingInterval * 0.55, 0.20))) {
                        displayedRange = newRange
                    }
                }
            }
        }
    }

    struct Range: Equatable { var min: Double; var max: Double }

    func dynamicRange(now: Date) -> Range {
        let all = store.endpoints.flatMap {
            store.engines[$0.id]?.results.compactMap { result -> Double? in
                guard let ms = result.latencyMs else { return nil }
                let age = now.timeIntervalSince(result.timestamp)
                guard age >= 0, age <= graphWindowSeconds else { return nil }
                return ms
            } ?? []
        }
        guard !all.isEmpty else { return Range(min: 0, max: 120) }
        let lo   = max(0, all.min()! - 5)
        let hi   = all.max()! * 1.10
        let span = max(hi - lo, 30)
        return Range(min: lo, max: lo + span)
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
    func displayPoints(from results: [PingResult], now: Date) -> [DisplayPingPoint] {
        let vals = results.compactMap { result -> DisplayPingPoint? in
            guard let ms = result.latencyMs else { return nil }
            let age = now.timeIntervalSince(result.timestamp)
            guard age >= 0 else { return nil }
            return DisplayPingPoint(timestamp: result.timestamp, latencyMs: ms)
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
            displayed[lastIdx] = DisplayPingPoint(timestamp: t, latencyMs: ms)
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
        let lines = gridValues()
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: size.height))
                p.addLine(to: CGPoint(x: size.width, y: size.height))
            }
            .stroke(Color.white.opacity(0.15), lineWidth: 0.75)

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

    func gridValues() -> [Double] {
        let step  = niceStep((maxMs - minMs) / 3)
        let first = ceil(minMs / step) * step
        return Array(stride(from: first, through: maxMs, by: step))
    }

    func niceStep(_ raw: Double) -> Double {
        let mag = pow(10, floor(log10(max(raw, 1))))
        let n   = raw / mag
        if n < 1.5 { return mag }
        if n < 3.5 { return 2 * mag }
        if n < 7.5 { return 5 * mag }
        return 10 * mag
    }
}

// ---------------------------------------------------------------------------
// Y-axis labels
// ---------------------------------------------------------------------------
struct YLabels: View {
    let size: CGSize; let minMs: Double; let maxMs: Double

    var body: some View {
        let lines = gridValues()
        let top = lines.max()
        return ZStack(alignment: .topLeading) {
            ForEach(lines, id: \.self) { ms in
                let y = CGFloat(1 - (ms - minMs) / (maxMs - minMs)) * size.height
                let isTop = ms == top
                Text("\(Int(ms))")
                    .font(.system(size: 7.5,
                                  weight: isTop ? .semibold : .medium,
                                  design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isTop ? 0.45 : 0.28))
                    .offset(x: 3, y: y - 9)
            }
        }
    }

    func gridValues() -> [Double] {
        let step  = niceStep((maxMs - minMs) / 3)
        let first = ceil(minMs / step) * step
        return Array(stride(from: first, through: maxMs, by: step))
    }

    func niceStep(_ raw: Double) -> Double {
        let mag = pow(10, floor(log10(max(raw, 1))))
        let n   = raw / mag
        if n < 1.5 { return mag }
        if n < 3.5 { return 2 * mag }
        if n < 7.5 { return 5 * mag }
        return 10 * mag
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
            pts.forEach { p.addLine(to: $0.point) }
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
        clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            return Pt(point: CGPoint(
                x: size.width * CGFloat(frac),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs)
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

    struct Pt { let point: CGPoint; let ms: Double }

    var body: some View {
        let pts = validPoints()
        guard pts.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            ZStack {
                ForEach(0 ..< pts.count - 1, id: \.self) { i in
                    let a   = pts[i].point
                    let b   = pts[i + 1].point
                    let col = latencyColor((pts[i].ms + pts[i + 1].ms) / 2)
                    let c1  = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
                    let c2  = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
                    Path { p in
                        p.move(to: a)
                        p.addCurve(to: b, control1: c1, control2: c2)
                    }
                    .stroke(col,
                            style: StrokeStyle(lineWidth: 1.8,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .shadow(color: col.opacity(0.5), radius: 3)
                }
            }
        )
    }

    func validPoints() -> [Pt] {
        clipPointsToWindow(points, now: now, windowSeconds: windowSeconds).compactMap { point in
            let age = now.timeIntervalSince(point.timestamp)
            guard age >= 0, age <= windowSeconds else { return nil }
            let frac = 1 - age / windowSeconds
            return Pt(point: CGPoint(
                x: size.width * CGFloat(frac),
                y: CGFloat(1 - (min(max(point.latencyMs, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: point.latencyMs)
        }
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
                .frame(width: pulse ? 16 : 7, height: pulse ? 16 : 7)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.9), radius: 4)
        }
        .onAppear { pulse = true }
    }
}
