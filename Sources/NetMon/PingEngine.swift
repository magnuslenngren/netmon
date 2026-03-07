import Foundation
import AppKit
import SwiftUI
import Darwin

// ---------------------------------------------------------------------------
// PingResult
// ---------------------------------------------------------------------------
struct PingResult: Identifiable {
    let id        = UUID()
    let timestamp: Date
    let latencyMs: Double?   // nil = timeout / unreachable
    let bytesIn: Double
    let bytesOut: Double
}

// ---------------------------------------------------------------------------
// Endpoint model
// ---------------------------------------------------------------------------
struct Endpoint: Identifiable, Codable, Equatable {
    var id:    UUID         = UUID()
    var label: String
    var host:  String
    var color: CodableColor

    static let defaults: [Endpoint] = [
        Endpoint(label: "Cloudflare", host: "1.1.1.1", color: CodableColor(.systemGreen)),
    ]
}

// ---------------------------------------------------------------------------
// CodableColor
// ---------------------------------------------------------------------------
struct CodableColor: Codable, Equatable {
    var r: Double; var g: Double; var b: Double; var a: Double

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        r = c.redComponent; g = c.greenComponent
        b = c.blueComponent; a = c.alphaComponent
    }

    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
    var swiftUIColor: Color { Color(nsColor) }
}

// ---------------------------------------------------------------------------
// PingEngine — uses /sbin/ping (ICMP, no root needed via subprocess)
// 1 packet, 56-byte payload (standard ping default), 1s timeout
// ---------------------------------------------------------------------------
final class PingEngine {
    let endpoint: Endpoint
    private(set) var results: [PingResult] = []
    private let maxHistory = 60
    private var timer: Timer?
    private var lastIOSnapshot: IOSnapshot?
    var onUpdate: (() -> Void)?

    init(endpoint: Endpoint) {
        self.endpoint = endpoint
    }

    func start(interval: TimeInterval = 1.0) {
        probe()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.probe()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Spawn /sbin/ping -c 1 -W 1000 -s 56 <host>
    // -c 1  : one packet
    // -W 1000: 1 second timeout (milliseconds on macOS)
    // -s 56 : 56-byte payload (standard, same as default ping)
    private func probe() {
        let host      = endpoint.host
        let startTime = Date()
        let process   = Process()
        let pipe      = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments     = ["-c", "1", "-W", "1000", "-s", "56", host]
        process.standardOutput = pipe
        process.standardError  = pipe

        process.terminationHandler = { [weak self] proc in
            let data   = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let ms     = Self.parse(output: output, fallbackElapsed: Date().timeIntervalSince(startTime))
            self?.record(PingResult(timestamp: startTime, latencyMs: ms, bytesIn: 0, bytesOut: 0))
        }

        do {
            try process.run()
        } catch {
            record(PingResult(timestamp: startTime, latencyMs: nil, bytesIn: 0, bytesOut: 0))
        }
    }

    // Parse "round-trip min/avg/max/stddev = 12.345/12.345/12.345/0.000 ms"
    // or    "64 bytes from 1.1.1.1: icmp_seq=0 ttl=55 time=12.345 ms"
    private static func parse(output: String, fallbackElapsed: TimeInterval) -> Double? {
        // Try "time=X ms" first (single packet line)
        if let range = output.range(of: #"time=(\d+\.?\d*)\s*ms"#,
                                     options: .regularExpression) {
            let match = output[range]
            if let numRange = match.range(of: #"[\d\.]+"#, options: .regularExpression) {
                return Double(match[numRange])
            }
        }
        // Try round-trip summary line
        if let range = output.range(of: #"= [\d.]+/([\d.]+)/"#,
                                     options: .regularExpression) {
            let match = output[range]            // "= min/avg/"
            let parts = match.dropFirst(2).split(separator: "/")
            if parts.count >= 2, let avg = Double(parts[1]) {
                return avg
            }
        }
        // Timeout / host unreachable
        return nil
    }

    private func record(_ result: PingResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let snap = IOSnapshot.capture()
            let delta = self.lastIOSnapshot.map { snap.delta(from: $0) } ?? IOSnapshot.zero
            self.lastIOSnapshot = snap

            let enriched = PingResult(timestamp: result.timestamp,
                                      latencyMs: result.latencyMs,
                                      bytesIn: Double(delta.inBytes),
                                      bytesOut: Double(delta.outBytes))
            self.results.append(enriched)
            if self.results.count > self.maxHistory {
                self.results.removeFirst(self.results.count - self.maxHistory)
            }
            self.onUpdate?()
        }
    }
}

private struct IOSnapshot {
    let inBytes: UInt64
    let outBytes: UInt64

    static let zero = IOSnapshot(inBytes: 0, outBytes: 0)

    static func capture() -> IOSnapshot {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return .zero }
        defer { freeifaddrs(first) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            defer { cursor = ifa.ifa_next }

            let flags = Int32(ifa.ifa_flags)
            let up = (flags & IFF_UP) != 0
            let loopback = (flags & IFF_LOOPBACK) != 0
            guard up, !loopback else { continue }
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let dataPtr = ifa.ifa_data else { continue }

            let netData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(netData.ifi_ibytes)
            tx += UInt64(netData.ifi_obytes)
        }
        return IOSnapshot(inBytes: rx, outBytes: tx)
    }

    func delta(from previous: IOSnapshot) -> IOSnapshot {
        IOSnapshot(inBytes: inBytes >= previous.inBytes ? inBytes - previous.inBytes : 0,
                   outBytes: outBytes >= previous.outBytes ? outBytes - previous.outBytes : 0)
    }
}
