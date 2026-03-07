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
    @Published var isCompact: Bool = false

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
            "pingInterval": pingInterval
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
    }
}
