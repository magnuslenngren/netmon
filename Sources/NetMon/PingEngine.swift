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
// ICMP helpers
// ---------------------------------------------------------------------------
private struct ICMPHeader {
    var type: UInt8      // 8 = echo request, 0 = echo reply
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequence: UInt16

    static let echoRequest: UInt8 = 8
    static let echoReply: UInt8   = 0
    static let headerSize         = 8
}

private func internetChecksum(_ data: Data) -> UInt16 {
    var sum: UInt32 = 0
    let bytes = [UInt8](data)
    var i = 0
    while i + 1 < bytes.count {
        sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
        i += 2
    }
    if i < bytes.count {
        sum += UInt32(bytes[i]) << 8
    }
    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }
    return ~UInt16(sum & 0xFFFF)
}

// ---------------------------------------------------------------------------
// PingEngine — raw ICMP socket (non-privileged SOCK_DGRAM, no root needed)
// ---------------------------------------------------------------------------
final class PingEngine {
    let endpoint: Endpoint
    private(set) var results: [PingResult] = []
    private let maxHistory = 60
    private var timerSource: DispatchSourceTimer?
    private var lastIOSnapshot: IOSnapshot?
    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "netmon.ping", qos: .userInitiated)
    private var sock: Int32 = -1
    private let identifier: UInt16
    private var sequenceNumber: UInt16 = 0
    private var inFlight = false
    private let timeoutSec: Double = 1.0
    private var resolvedAddr: sockaddr_in?

    init(endpoint: Endpoint) {
        self.endpoint = endpoint
        self.identifier = UInt16(truncatingIfNeeded: arc4random())
    }

    func start(interval: TimeInterval = 1.0) {
        queue.async { [weak self] in
            self?.resolveHost()
            self?.openSocket()
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.probe()
        }
        timer.resume()
        timerSource = timer
    }

    func stop() {
        timerSource?.cancel()
        timerSource = nil
        queue.async { [weak self] in
            guard let self, self.sock >= 0 else { return }
            close(self.sock)
            self.sock = -1
        }
    }

    // MARK: - Socket setup

    private func resolveHost() {
        let host = endpoint.host
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return }
        defer { freeaddrinfo(info) }

        if info.pointee.ai_family == AF_INET, info.pointee.ai_addrlen >= MemoryLayout<sockaddr_in>.size {
            var addr = sockaddr_in()
            memcpy(&addr, info.pointee.ai_addr, Int(info.pointee.ai_addrlen))
            resolvedAddr = addr
        }
    }

    private func openSocket() {
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if sock < 0 { return }

        // Set receive timeout so recvfrom doesn't block forever
        var tv = timeval(tv_sec: Int(timeoutSec), tv_usec: __darwin_suseconds_t((timeoutSec.truncatingRemainder(dividingBy: 1.0)) * 1_000_000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    // MARK: - Probe

    private func probe() {
        guard !inFlight else { return }
        if sock < 0 || resolvedAddr == nil {
            // Socket or DNS failed — try to recover and continue this probe cycle.
            resolveHost()
            if sock < 0 { openSocket() }
            if sock < 0 || resolvedAddr == nil {
                record(PingResult(timestamp: Date(), latencyMs: nil, bytesIn: 0, bytesOut: 0))
                return
            }
        }
        guard var dest = resolvedAddr else {
            record(PingResult(timestamp: Date(), latencyMs: nil, bytesIn: 0, bytesOut: 0))
            return
        }

        inFlight = true
        let seq = sequenceNumber
        sequenceNumber &+= 1

        // Build ICMP echo request (8-byte header + 48-byte payload = 56 bytes standard)
        let payloadSize = 48
        var packet = Data(count: ICMPHeader.headerSize + payloadSize)
        packet[0] = ICMPHeader.echoRequest
        packet[1] = 0 // code
        packet[2] = 0; packet[3] = 0 // checksum placeholder
        packet[4] = UInt8(identifier >> 8); packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(seq >> 8); packet[7] = UInt8(seq & 0xFF)

        // Fill payload with timestamp for identification
        let now = Date()
        var ts = now.timeIntervalSince1970
        withUnsafeBytes(of: &ts) { buf in
            let count = min(buf.count, payloadSize)
            packet.replaceSubrange(ICMPHeader.headerSize ..< ICMPHeader.headerSize + count,
                                   with: buf.prefix(count))
        }

        // Compute checksum
        let cksum = internetChecksum(packet)
        packet[2] = UInt8(cksum >> 8); packet[3] = UInt8(cksum & 0xFF)

        // Send
        let sent = packet.withUnsafeBytes { buf in
            withUnsafeMutablePointer(to: &dest) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent > 0 else {
            inFlight = false
            record(PingResult(timestamp: now, latencyMs: nil, bytesIn: 0, bytesOut: 0))
            return
        }

        // Receive reply
        var recvBuf = [UInt8](repeating: 0, count: 256)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let recvTime: Date

        // Loop to skip non-matching replies within the timeout window
        let deadline = now.addingTimeInterval(timeoutSec)
        while true {
            fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &fromAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &fromLen)
                }
            }
            let t = Date()

            if n < 0 {
                // Timeout or error
                inFlight = false
                record(PingResult(timestamp: now, latencyMs: nil, bytesIn: 0, bytesOut: 0))
                return
            }

            // Determine ICMP header offset — macOS may or may not include the IP header
            var icmpOffset = 0
            if n > 0 && (recvBuf[0] >> 4) == 4 {
                // IPv4 header present; IHL field gives header length in 32-bit words
                icmpOffset = Int(recvBuf[0] & 0x0F) * 4
            }

            if n >= icmpOffset + ICMPHeader.headerSize {
                let replyType = recvBuf[icmpOffset]
                let replyId = UInt16(recvBuf[icmpOffset + 4]) << 8 | UInt16(recvBuf[icmpOffset + 5])
                let replySeq = UInt16(recvBuf[icmpOffset + 6]) << 8 | UInt16(recvBuf[icmpOffset + 7])
                let replyMatchesDestination = fromAddr.sin_addr.s_addr == dest.sin_addr.s_addr

                if replyType == ICMPHeader.echoReply &&
                    replyId == identifier &&
                    replySeq == seq &&
                    replyMatchesDestination {
                    recvTime = t
                    break
                }
            }

            // Not our reply — check if we still have time
            if Date() >= deadline {
                inFlight = false
                record(PingResult(timestamp: now, latencyMs: nil, bytesIn: 0, bytesOut: 0))
                return
            }
        }

        let latencyMs = recvTime.timeIntervalSince(now) * 1000.0
        inFlight = false
        record(PingResult(timestamp: now, latencyMs: latencyMs, bytesIn: 0, bytesOut: 0))
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
