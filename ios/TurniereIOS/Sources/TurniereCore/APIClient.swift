import Foundation

public enum APIError: Error, LocalizedError, Equatable {
    case invalidCode, notFound, status(Int), invalidResponse, invalidScore
    public var errorDescription: String? {
        switch self {
        case .invalidScore: return L10n.text("proposal.invalid")
        case .invalidCode: return L10n.text("error.code")
        case .notFound: return L10n.text("error.notFound")
        case .status(let code): return L10n.format("error.status", code)
        case .invalidResponse: return L10n.text("error.response")
        }
    }
}

public protocol TournamentServing: Sendable {
    func tournaments() async throws -> [TournamentSummary]
    func tournament(code: String) async throws -> Tournament
}

public struct APIClient: TournamentServing, Sendable {
    public static let productionURL = URL(string: "https://api.turnie.re")!
    private let baseURL: URL
    private let session: URLSession
    public init(baseURL: URL = productionURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
    }
    public func tournaments() async throws -> [TournamentSummary] { try await get("tournaments") }
    public func tournament(code: String) async throws -> Tournament {
        let reference = try TournamentCode.parse(code)
        // Rails find() accepts numeric prefixes. Resolve public codes first and verify identity.
        let summaries = try await tournaments()
        if let summary = summaries.first(where: { $0.code == reference }) {
            let result: Tournament = try await get("tournaments/\(summary.id)")
            guard result.id == summary.id && result.code == reference else { throw APIError.invalidResponse }
            return result
        }
        guard reference.allSatisfy(\.isNumber), let id = Int(reference) else { throw APIError.notFound }
        let result: Tournament = try await get("tournaments/\(id)")
        guard result.id == id else { throw APIError.invalidResponse }
        return result
    }
    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 404 { throw APIError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
        do { return try Self.decoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
