import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

let base = Date(timeIntervalSince1970: 0)
var checks = 0
for interval in [0.2, 1.0, 2.0] {
    var history: [PingResult] = []
    var seconds = 0.0
    for index in 0..<1_200 {
        // Exercise regular samples, timing jitter, packet loss, and long gaps.
        seconds += interval * (index % 7 == 0 ? 1.2 : 1.0)
        if index == 800 { seconds += 75 }
        history.append(PingResult(timestamp: base.addingTimeInterval(seconds),
                                  latencyMs: index % 11 == 0 ? nil : Double(index % 100),
                                  bytesIn: Double(index * 10), bytesOut: Double(index * 5)))
        GraphHistory.prune(&history, interval: interval)
        guard seconds > 70 else { continue }
        for lag in [max(interval, 0.2), GraphHistory.maximumDisplayLag(interval: interval)] {
            for phase in [0.0, 0.25, 0.75] {
                let now = base.addingTimeInterval(seconds - lag + phase * interval)
                let boundary = now.addingTimeInterval(-GraphHistory.windowSeconds)
                let points = history.map { DisplaySeriesPoint(timestamp: $0.timestamp, value: $0.bytesIn) }
                let clipped = clipPointsToWindow(points, now: now, windowSeconds: GraphHistory.windowSeconds)
                // A gap can cover the whole window; once there is a visible
                // sample again, its left-hand segment must reach the boundary.
                if points.contains(where: { $0.timestamp >= boundary && $0.timestamp <= now }) {
                    require(clipped.first?.timestamp == boundary, "Left edge detached at interval \(interval), sample \(index)")
                    let latency = history.map { DisplayPingPoint(timestamp: $0.timestamp, latencyMs: $0.latencyMs ?? 0, isLoss: $0.latencyMs == nil) }
                    require(clipPointsToWindow(latency, now: now, windowSeconds: GraphHistory.windowSeconds).first?.timestamp == boundary,
                            "Latency edge detached")
                    checks += 1
                }
            }
        }
        require(history.count < Int(ceil(65 / interval)) + 5, "History grew without bound")
    }
}
print("Passed \(checks) left-edge checks across sample rates, timing jitter, loss, and gaps.")
