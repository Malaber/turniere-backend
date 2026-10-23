import Foundation
import Observation
import TurniereCore

@MainActor @Observable
final class TournamentStore {
    var library = TournamentLibrary()
    var tournaments: [TournamentSummary] = []
    var listError: String?
    var errors: [String: String] = [:]
    var loading = Set<String>()
    var storageError: String?
    private let api: any TournamentServing
    private let storageURL: URL
    private var storageHealthy = true
    private var aliases: [String: String] = [:]

    init() {
        var demo = false
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #endif
        api = demo ? DemoAPI(offline: ProcessInfo.processInfo.arguments.contains("--demo-offline")) : APIClient()
        let root = URL.applicationSupportDirectory.appendingPathComponent("re.turnie", isDirectory: true)
        storageURL = root.appendingPathComponent(demo ? "demo-library.json" : "library.json")
        #if DEBUG
        if demo && ProcessInfo.processInfo.arguments.contains("--reset-demo") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        #endif
        do { library = try TournamentLibrary.load(from: storageURL) }
        catch {
            storageHealthy = false
            storageError = L10n.text("error.storage.read")
        }
    }
    func discover() async {
        guard !loading.contains("index") else { return }
        loading.insert("index")
        defer { loading.remove("index") }
        do {
            tournaments = try await api.tournaments().sorted { $0.id > $1.id }
            listError = nil
        } catch is CancellationError {} catch {
            listError = L10n.message(for: error)
        }
    }
    func refresh(_ code: String) async {
        guard !loading.contains(code) else { return }
        loading.insert(code)
        defer { loading.remove(code) }
        do {
            let tournament = try await api.tournament(code: code)
            try Task.checkCancellation()
            aliases[code] = tournament.code
            library.update(tournament)
            errors[code] = nil
            persist()
        } catch is CancellationError {} catch {
            if (error as? URLError)?.code != .cancelled { errors[code] = L10n.message(for: error) }
        }
    }
    func entry(_ code: String) -> SavedTournament? { library.entries.first { $0.id == (aliases[code] ?? code) || String($0.tournament.id) == code } }
    func favorite(_ id: Int?, in code: String) { library.favorite(id, in: entry(code)?.id ?? code); persist() }
    func remove(_ code: String) { library.remove(code); persist() }
    private func persist() {
        guard storageHealthy else { return }
        do { try library.save(to: storageURL); storageError = nil }
        catch { storageError = L10n.text("error.storage.write") }
    }
}

// Deterministic UI fixture; enabled only by a DEBUG launch argument, with no network calls.
struct DemoAPI: TournamentServing {
    let offline: Bool

    func tournaments() async throws -> [TournamentSummary] {
        if offline { throw URLError(.notConnectedToInternet) }
        guard let url = Bundle.main.url(forResource: "demo-index", withExtension: "json") else { throw APIError.invalidResponse }
        return try APIClient.decoder().decode([TournamentSummary].self, from: Data(contentsOf: url))
    }
    func tournament(code: String) async throws -> Tournament {
        if offline { throw URLError(.notConnectedToInternet) }
        guard code == "abc123" else { throw APIError.notFound }
        guard let url = Bundle.main.url(forResource: "demo-tournament", withExtension: "json") else { throw APIError.invalidResponse }
        return try APIClient.decoder().decode(Tournament.self, from: Data(contentsOf: url))
    }
}
