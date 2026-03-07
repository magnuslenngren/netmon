import SwiftUI

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

    var body: some View {
        GeometryReader { geo in
            let sz    = geo.size
            let range = dynamicRange()

            ZStack(alignment: .topLeading) {
                GridLines(size: sz, minMs: range.min, maxMs: range.max)

                ForEach(store.endpoints, id: \.id) { ep in
                    if let eng = store.engines[ep.id], eng.results.count >= 2 {
                        AreaShape(results: eng.results,
                                  size: sz, minMs: range.min, maxMs: range.max)
                        LineShape(results: eng.results,
                                  size: sz, minMs: range.min, maxMs: range.max)
                    }
                }

                ForEach(store.endpoints, id: \.id) { ep in
                    if let eng = store.engines[ep.id],
                       let ms  = eng.results.last?.latencyMs {
                        LiveDot(color: latencyColor(ms))
                            .position(x: sz.width,
                                      y: yFrac(ms, range) * sz.height)
                    }
                }

                YLabels(size: sz, minMs: range.min, maxMs: range.max)
            }
        }
    }

    struct Range { var min: Double; var max: Double }

    func dynamicRange() -> Range {
        let all = store.endpoints.flatMap {
            store.engines[$0.id]?.results.compactMap(\.latencyMs) ?? []
        }
        guard !all.isEmpty else { return Range(min: 0, max: 120) }
        let lo   = max(0, all.min()! - 5)
        let hi   = all.max()! * 1.15
        let span = max(hi - lo, 30)
        return Range(min: lo, max: lo + span)
    }

    func yFrac(_ ms: Double, _ r: Range) -> CGFloat {
        CGFloat(1 - (min(max(ms, r.min), r.max) - r.min) / (r.max - r.min))
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
        return ZStack(alignment: .topLeading) {
            ForEach(lines, id: \.self) { ms in
                let y = CGFloat(1 - (ms - minMs) / (maxMs - minMs)) * size.height
                Text("\(Int(ms))")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.28))
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
    let size:    CGSize
    let minMs:   Double
    let maxMs:   Double

    var body: some View {
        let pts      = validPoints()
        let latestMs = results.compactMap(\.latencyMs).last ?? 20
        let color    = latencyColor(latestMs)
        guard pts.count >= 2 else { return AnyView(EmptyView()) }

        let path = Path { p in
            p.move(to: CGPoint(x: pts[0].x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
            p.closeSubpath()
        }
        return AnyView(
            path.fill(LinearGradient(
                colors: [color.opacity(0.20), color.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ))
        )
    }

    func validPoints() -> [CGPoint] {
        results.compactMap(\.latencyMs).enumerated().map { i, ms in
            let total = results.compactMap(\.latencyMs).count
            return CGPoint(
                x: size.width  * CGFloat(i) / CGFloat(max(total - 1, 1)),
                y: CGFloat(1 - (min(max(ms, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Line — each segment colored by the latency at that point
// ---------------------------------------------------------------------------
struct LineShape: View {
    let results: [PingResult]
    let size:    CGSize
    let minMs:   Double
    let maxMs:   Double

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
        let vals = results.compactMap(\.latencyMs)
        guard vals.count >= 2 else { return [] }
        return vals.enumerated().map { i, ms in
            Pt(point: CGPoint(
                x: size.width  * CGFloat(i) / CGFloat(vals.count - 1),
                y: CGFloat(1 - (min(max(ms, minMs), maxMs) - minMs) / (maxMs - minMs)) * size.height
            ), ms: ms)
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
