import Foundation

public enum AppServer: String, CaseIterable, Sendable {
    case production, beta
    public var apiURL: URL { URL(string: self == .beta ? "https://beta.api.turnie.re" : "https://api.turnie.re")! }
    public var webURL: URL { URL(string: self == .beta ? "https://beta.turnie.re" : "https://turnie.re")! }
}

public struct PlayerTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let client: String
    public let uid: String
    public init(accessToken: String, client: String, uid: String) {
        self.accessToken = accessToken; self.client = client; self.uid = uid
    }
    public func updated(from response: HTTPURLResponse) -> Self {
        guard let token = response.value(forHTTPHeaderField: "access-token"), !token.isEmpty else { return self }
        return Self(accessToken: token, client: response.value(forHTTPHeaderField: "client") ?? client,
                    uid: response.value(forHTTPHeaderField: "uid") ?? uid)
    }
}

public struct TeamProposal: Decodable, Sendable {
    public let teamId: Int
    public let scores: [String: Int]
}

public struct PlayerMatch: Decodable, Identifiable, Sendable {
    public let matchId: Int
    public var id: Int { matchId }
    public let officialScores: [String: Int?]
    public let eligibleTeamIds: [Int]
    public let accepting: Bool
    public let locked: Bool
    public let revision: Int
    public let proposals: [TeamProposal]
    public let teams: [Team]
}

public struct PlayerMatchList: Decodable, Sendable { public let matches: [PlayerMatch] }

public enum ProposalScores {
    public static func validated(_ scores: [String: String], teams: [Int]) throws -> [String: Int] {
        guard teams.count == 2, Set(teams).count == 2, Set(scores.keys) == Set(teams.map(String.init)) else {
            throw APIError.invalidScore
        }
        var result: [String: Int] = [:]
        for (id, text) in scores {
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(text), (0...1000).contains(value) else { throw APIError.invalidScore }
            result[id] = value
        }
        return result
    }
}

// Never follow authentication redirects to a different server.
private final class PlayerRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct PlayerHTTPError: Error, Sendable {
    public let status: Int
    public let tokens: PlayerTokens?
}

public struct PlayerAPI: Sendable {
    private let baseURL: URL
    private let session: URLSession
    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: config, delegate: PlayerRedirectPolicy(), delegateQueue: nil)
    }
    public func signIn(email: String, password: String) async throws -> PlayerTokens {
        let (_, response) = try await request("POST", "users/sign_in", body: ["email": email, "password": password])
        guard let token = response.value(forHTTPHeaderField: "access-token"), !token.isEmpty,
              let client = response.value(forHTTPHeaderField: "client"), let uid = response.value(forHTTPHeaderField: "uid") else {
            throw APIError.invalidResponse
        }
        return PlayerTokens(accessToken: token, client: client, uid: uid)
    }
    public func signOut(tokens: PlayerTokens) async throws { _ = try await request("DELETE", "users/sign_out", tokens: tokens) }
    public func matches(tournamentID: Int, tokens: PlayerTokens) async throws -> (PlayerMatchList, PlayerTokens) {
        let (data, response) = try await request("GET", "tournaments/\(tournamentID)/player_score_matches", tokens: tokens)
        return (try APIClient.decoder().decode(PlayerMatchList.self, from: data), tokens.updated(from: response))
    }
    public func submit(matchID: Int, teamID: Int, scores: [String: Int], tokens: PlayerTokens) async throws -> (PlayerMatch, PlayerTokens) {
        let (data, response) = try await request("PATCH", "matches/\(matchID)/score_proposal", tokens: tokens,
                                               body: ["team_id": teamID, "scores": scores])
        return (try APIClient.decoder().decode(PlayerMatch.self, from: data), tokens.updated(from: response))
    }
    private func request(_ method: String, _ path: String, tokens: PlayerTokens? = nil,
                         body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let tokens {
            request.setValue(tokens.accessToken, forHTTPHeaderField: "access-token")
            request.setValue(tokens.client, forHTTPHeaderField: "client")
            request.setValue(tokens.uid, forHTTPHeaderField: "uid")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.status(401) }
            throw PlayerHTTPError(status: http.statusCode, tokens: tokens?.updated(from: http))
        }
        return (data, http)
    }
}
