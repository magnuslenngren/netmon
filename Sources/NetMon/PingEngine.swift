import Foundation
import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// PingResult
// ---------------------------------------------------------------------------
struct PingResult: Identifiable {
    let id        = UUID()
    let timestamp: Date
    let latencyMs: Double?   // nil = timeout / unreachable
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
            self?.record(PingResult(timestamp: startTime, latencyMs: ms))
        }

        do {
            try process.run()
        } catch {
            record(PingResult(timestamp: startTime, latencyMs: nil))
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
            self.results.append(result)
            if self.results.count > self.maxHistory {
                self.results.removeFirst(self.results.count - self.maxHistory)
            }
            self.onUpdate?()
        }
    }
}
