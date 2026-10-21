import Foundation
import Testing
@testable import TurniereCore

private func fixture() throws -> Tournament {
    let url = Bundle.module.url(forResource: "tournament", withExtension: "json", subdirectory: "Fixtures")!
    return try APIClient.decoder().decode(Tournament.self, from: Data(contentsOf: url))
}

@Test func codeAndLinks() throws {
    #expect(try TournamentCode.parse(" ABC123 \n") == "abc123")
    #expect(try TournamentCode.parse("https://turnie.re/t/11") == "11")
    #expect(try TournamentCode.parse("https://turnie.re/t/abc123/fullscreen?ref=friend") == "abc123")
    for input in ["", "../users", "https://evil.example/t/abc123", "abc12", "https://turnie.re/t/abc12", "https://turnie.re.evil/t/abc123", "https://user:password@turnie.re/t/abc123"] {
        #expect(throws: APIError.invalidCode) { try TournamentCode.parse(input) }
    }
}

@Test func scoresAndFavoriteSchedule() throws {
    let tournament = try fixture()
    #expect(tournament.matches.count == 4)
    #expect(tournament.matches(for: 3).map(\.id) == [2, 3])
    #expect(tournament.nextMatch(for: 1)?.id == 1)
    #expect(tournament.nextMatch(for: 3)?.id == 2)
    let pending = tournament.matches[1]
    #expect(pending.points(for: pending.matchScores[0]) == "–")
    let decider = tournament.matches[3]
    #expect(decider.points(for: decider.matchScores[0]) == "2")
    #expect(tournament.stages[0].groups[0].standings.map(\.position) == [1,2,3])
    #expect(tournament.webURL.absoluteString == "https://turnie.re/t/1")
}

@Test func libraryPersistsFavoriteAndSnapshot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var library = TournamentLibrary()
    library.update(try fixture(), at: Date(timeIntervalSince1970: 42))
    library.favorite(2, in: "abc123")
    library.update(try fixture(), at: Date(timeIntervalSince1970: 43))
    try library.save(to: url)
    var restored = try TournamentLibrary.load(from: url)
    #expect(restored.entries.count == 1)
    #expect(restored.entries[0].favoriteTeamID == 2)
    #expect(restored.entries[0].fetchedAt == Date(timeIntervalSince1970: 43))
    restored.favorite(9999, in: "abc123")
    #expect(restored.entries[0].favoriteTeamID == 2)
    restored.favorite(nil, in: "abc123")
    #expect(restored.entries[0].favoriteTeamID == nil)
    restored.remove("abc123")
    #expect(restored.entries.isEmpty)
    try Data("broken".utf8).write(to: url)
    #expect(throws: (any Error).self) { try TournamentLibrary.load(from: url) }
    #expect(try String(contentsOf: url, encoding: .utf8) == "broken")
}

@Test func timestampsAcceptRailsPrecision() {
    #expect(APIDate.parse("2026-05-01T12:00:00Z") == APIDate.parse("2026-05-01T14:00:00.000+02:00"))
    #expect(APIDate.parse(nil) == nil)
    #expect(APIDate.parse("invalid") == nil)
}

final class ReadOnlyProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET", request.httpBody == nil, request.value(forHTTPHeaderField: "Accept") == "application/json" else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidResponse); return
        }
        let path = request.url!.path
        var status = 200
        var data = Data("[{\"id\":1,\"name\":\"Sommercup\",\"code\":\"abc123\"}]".utf8)
        if path.hasSuffix("/1") || path.hasSuffix("/2") {
            data = try! Data(contentsOf: Bundle.module.url(forResource: "tournament", withExtension: "json", subdirectory: "Fixtures")!)
        } else if path.hasSuffix("/404") { status = 404 }
        else if path.hasSuffix("/500") { status = 500 }
        else if path.hasSuffix("/501") { data = Data("not json".utf8) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func clientUsesOnlyGETAndReportsFailures() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReadOnlyProtocol.self]
    let api = APIClient(session: URLSession(configuration: config))
    #expect(try await api.tournaments().count == 1)
    #expect(try await api.tournament(code: "abc123").teams.count == 3)
    await #expect(throws: APIError.invalidResponse) { try await api.tournament(code: "2") }
    await #expect(throws: APIError.notFound) { try await api.tournament(code: "404") }
    await #expect(throws: APIError.status(500)) { try await api.tournament(code: "500") }
    await #expect(throws: APIError.invalidResponse) { try await api.tournament(code: "501") }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TURNIERE_LIVE_READ_ONLY"] == "1"))
func productionReadOnlyContract() async throws {
    let api = APIClient()
    let summaries = try await api.tournaments()
    #expect(!summaries.isEmpty)
    for summary in summaries.prefix(3) {
        let tournament = try await api.tournament(code: summary.code)
        #expect(tournament.id == summary.id)
        #expect(tournament.code == summary.code)
        #expect(!tournament.name.isEmpty)
    }
}
