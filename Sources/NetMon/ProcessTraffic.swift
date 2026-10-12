import Foundation
import Combine

enum TrafficDirection: String, Identifiable {
    case down, up
    var id: String { rawValue }
    var title: String { self == .down ? "Top Downloads" : "Top Uploads" }
}

struct ProcessTraffic: Identifiable {
    let id: Int32
    let name: String
    let bytesIn: Double
    let bytesOut: Double

    func rate(for direction: TrafficDirection) -> Double {
        direction == .down ? bytesIn : bytesOut
    }

    static func top(_ rows: [Self], direction: TrafficDirection) -> [Self] {
        Array(rows.filter { $0.rate(for: direction) > 0 }.sorted {
            let lhs = $0.rate(for: direction), rhs = $1.rate(for: direction)
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }.prefix(5))
    }
}

// Each invocation requests two samples one second apart. The first contains
// lifetime counters even in delta mode; only the second is a bandwidth sample.
struct ProcessTrafficParser {
    static func parse(_ output: String) -> [ProcessTraffic]? {
        var columns: [String] = []
        var sampleCount = 0
        var rows: [ProcessTraffic] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if fields.first == "", fields.contains("bytes_in"), fields.contains("bytes_out") {
                columns = fields
                sampleCount += 1
                rows = []
                continue
            }
            guard sampleCount == 2,
                  let input = columns.firstIndex(of: "bytes_in"),
                  let output = columns.firstIndex(of: "bytes_out"),
                  fields.count > max(input, output),
                  let identity = fields.first,
                  let dot = identity.lastIndex(of: "."),
                  let pid = Int32(identity[identity.index(after: dot)...]),
                  let received = Double(fields[input]), let sent = Double(fields[output]),
                  received.isFinite, sent.isFinite else { continue }
            rows.append(ProcessTraffic(id: pid, name: String(identity[..<dot]),
                                       bytesIn: max(0, received), bytesOut: max(0, sent)))
        }
        return sampleCount == 2 ? rows : nil
    }
}

final class ProcessTrafficStore: ObservableObject {
    @Published private(set) var rows: [ProcessTraffic] = []
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    private var process: Process?
    private var session = UUID()
    private var timeout: DispatchWorkItem?

    func start() {
        guard process == nil else { return }
        rows = []
        isLoading = true
        error = nil
        session = UUID()
        sample(token: session)
    }

    private func sample(token: UUID) {
        guard session == token else { return }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // Continuous CSV output is block-buffered when piped. A bounded run
        // flushes at exit, delivering a complete one-second delta promptly.
        task.arguments = ["-L", "2", "-P", "-n", "-x", "-d", "-s", "1",
                          "-t", "external", "-J", "bytes_in,bytes_out"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            process = task
        } catch {
            fail("Unable to read process bandwidth. Close this list and try again.")
            return
        }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.session == token, self.process === task else { return }
            self.stop()
            self.fail("Bandwidth measurement timed out. Close this list and try again.")
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let handle = pipe.fileHandleForReading
            let data = handle.readDataToEndOfFile()
            try? handle.close()
            task.waitUntilExit()
            let result = task.terminationStatus == 0
                ? ProcessTrafficParser.parse(String(decoding: data, as: UTF8.self)) : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session == token else { return }
                self.timeout?.cancel()
                self.timeout = nil
                self.process = nil
                guard let result else {
                    self.fail("Process bandwidth is unavailable. Close this list and try again.")
                    return
                }
                self.rows = result
                self.isLoading = false
                self.sample(token: token)
            }
        }
    }

    private func fail(_ message: String) {
        rows = []
        isLoading = false
        error = message
    }

    func stop() {
        session = UUID()
        timeout?.cancel()
        timeout = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    deinit {
        timeout?.cancel()
        if let process, process.isRunning { process.terminate() }
    }
}
