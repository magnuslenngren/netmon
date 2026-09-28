import Foundation

enum GraphHistory {
    static let windowSeconds: TimeInterval = 60

    static func maximumDisplayLag(interval: TimeInterval) -> TimeInterval {
        max(interval, 0.2) * 1.5
    }

    static func prune(_ results: inout [PingResult], interval: TimeInterval) {
        guard let latest = results.last else { return }
        let boundary = latest.timestamp.addingTimeInterval(
            -windowSeconds - maximumDisplayLag(interval: interval)
        )
        // Keep a real sample before the earliest possible visible boundary.
        // The clipping code needs both endpoints of the segment leaving view.
        var removeCount = 0
        while removeCount + 1 < results.count,
              results[removeCount + 1].timestamp < boundary {
            removeCount += 1
        }
        if removeCount > 0 {
            results.removeFirst(removeCount)
        }
    }
}
