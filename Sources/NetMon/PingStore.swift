import Foundation
import Combine
import AppKit

// ---------------------------------------------------------------------------
// PingStore  –  ObservableObject driving the UI
// ---------------------------------------------------------------------------
final class PingStore: ObservableObject {
    private static let forcedEndpoint = Endpoint(label: "Cloudflare",
                                                 host: "1.1.1.1",
                                                 color: CodableColor(.systemGreen))
    @Published var endpoints: [Endpoint] = [] {
        didSet { save(); restart() }
    }
    @Published var engines: [UUID: PingEngine] = [:]
    @Published var alwaysOnTop: Bool = true {
        didSet {
            save()
            applyWindowLevel()
        }
    }
    @Published var pingInterval: Double = 1.0 {
        didSet { save(); restart() }
    }
    @Published var isCompact: Bool = false {
        didSet { save() }
    }
    @Published var showLatencyGraph: Bool = true {
        didSet { save() }
    }
    @Published var showTrafficGraph: Bool = true {
        didSet { save() }
    }
    @Published var tintLevel: Int = 2 {
        didSet {
            if tintLevel < 0 {
                tintLevel = 0
                return
            }
            if tintLevel > 4 {
                tintLevel = 4
                return
            }
            save()
        }
    }

    private let defaultsKey = "netmon.config"

    init() {
        load()
        endpoints = [Self.forcedEndpoint]
        restart()
    }

    // MARK: – Engine lifecycle
    func restart() {
        engines.values.forEach { $0.stop() }
        engines = [:]
        for ep in endpoints {
            let eng = PingEngine(endpoint: ep)
            eng.onUpdate = { [weak self] in self?.objectWillChange.send() }
            eng.start(interval: pingInterval)
            engines[ep.id] = eng
        }
    }

    func results(for id: UUID) -> [PingResult] {
        engines[id]?.results ?? []
    }

    // MARK: – Window level
    private func applyWindowLevel() {
        for window in NSApp.windows {
            window.level = alwaysOnTop ? .floating : .normal
        }
    }

    // MARK: – Persistence
    private func save() {
        let data: [String: Any] = [
            "endpoints":    (try? JSONEncoder().encode(endpoints)) as Any,
            "alwaysOnTop":  alwaysOnTop,
            "pingInterval": pingInterval,
            "isCompact":    isCompact,
            "showLatencyGraph": showLatencyGraph,
            "showTrafficGraph": showTrafficGraph,
            "tintLevel": tintLevel
        ]
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return }
        if let blob = data["endpoints"] as? Data,
           let eps  = try? JSONDecoder().decode([Endpoint].self, from: blob) {
            endpoints = eps
        }
        alwaysOnTop  = data["alwaysOnTop"]  as? Bool   ?? true
        pingInterval = data["pingInterval"] as? Double ?? 1.0
        isCompact    = data["isCompact"]    as? Bool   ?? false
        showLatencyGraph = data["showLatencyGraph"] as? Bool ?? true
        showTrafficGraph = data["showTrafficGraph"] as? Bool ?? true
        tintLevel = data["tintLevel"] as? Int ?? 2
    }
}
