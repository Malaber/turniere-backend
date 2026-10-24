import Foundation
import Testing
@testable import TurniereCore

private let proposalJSON = """
{"match_id":1,"official_scores":{"1":0,"2":null},"eligible_team_ids":[1],"accepting":true,"locked":false,"revision":1,"proposals":[{"team_id":1,"scores":{"1":7,"2":10}}],"teams":[{"id":1,"name":"Blue"},{"id":2,"name":"Gold"}]}
"""

final class PlayerProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let path = request.url!.path
        var result = "{}"
        var status = 200
        if path == "/users/sign_in" {
            #expect(request.httpMethod == "POST")
            let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: String]
            #expect(json == ["email": "player@example.test", "password": "secret"])
            #expect(request.value(forHTTPHeaderField: "access-token") == nil)
        } else {
            #expect(request.value(forHTTPHeaderField: "access-token") == "token")
            #expect(request.value(forHTTPHeaderField: "client") == "client")
            #expect(request.value(forHTTPHeaderField: "uid") == "player@example.test")
            if path == "/matches/1/score_proposal" {
                #expect(request.httpMethod == "PATCH")
                let json = try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]
                #expect(json?["team_id"] as? Int == 1)
                #expect(json?["scores"] as? [String: Int] == ["1": 7, "2": 10])
                #expect(json?.keys.count == 2)
                result = proposalJSON
            } else if path == "/users/sign_out" { #expect(request.httpMethod == "DELETE") }
            else {
                #expect(request.httpMethod == "GET")
                if path.contains("/401/") { status = 401 }
                else if path.contains("/409/") { status = 409 }
                result = "{\"matches\":[\(proposalJSON)]}"
            }
        }
        let headers = ["access-token": path == "/users/sign_in" ? "token" : "rotated", "client": "client", "uid": "player@example.test"]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func playerRequestsAuthenticateRotateAndSubmitOnlyScores() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PlayerProtocol.self]
    let api = PlayerAPI(baseURL: AppServer.beta.apiURL, session: URLSession(configuration: config))
    let tokens = try await api.signIn(email: "player@example.test", password: "secret")
    let (list, rotated) = try await api.matches(tournamentID: 5, tokens: tokens)
    #expect(rotated.accessToken == "rotated")
    #expect(list.matches.first?.eligibleTeamIds == [1])
    #expect(list.matches.first?.proposals.first?.scores == ["1": 7, "2": 10])
    let (result, _) = try await api.submit(matchID: 1, teamID: 1, scores: ["1": 7, "2": 10], tokens: tokens)
    #expect(result.officialScores["1"] == 0)
    await #expect(throws: APIError.status(401)) { try await api.matches(tournamentID: 401, tokens: tokens) }
    do {
        _ = try await api.matches(tournamentID: 409, tokens: tokens)
        Issue.record("Expected conflict")
    } catch let error as PlayerHTTPError {
        #expect(error.status == 409)
        #expect(error.tokens?.accessToken == "rotated")
    }
    try await api.signOut(tokens: tokens)
}

@Test func scoreValidationRejectsInvalidAndExtraValues() throws {
    #expect(try ProposalScores.validated(["1": "0", "2": "1000"], teams: [1, 2]) == ["1": 0, "2": 1000])
    for invalid in ["", "-1", "1001", "1.5", "abc", "１２", " 7"] {
        #expect(throws: APIError.invalidScore) { try ProposalScores.validated(["1": invalid, "2": "10"], teams: [1, 2]) }
    }
    #expect(throws: APIError.invalidScore) { try ProposalScores.validated(["1": "7", "2": "10", "3": "5"], teams: [1, 2]) }
    #expect(throws: APIError.invalidScore) { try ProposalScores.validated(["1": "7"], teams: [1, 2]) }
}

@Test func favoriteGroupsExcludeOtherTeamsGroups() throws {
    let url = Bundle.module.url(forResource: "tournament", withExtension: "json", subdirectory: "Fixtures")!
    let tournament = try APIClient.decoder().decode(Tournament.self, from: Data(contentsOf: url))
    #expect(tournament.groups(for: 1).count == 1)
    #expect(tournament.groups(for: 999).isEmpty)
    #expect(tournament.groups(for: 1).allSatisfy { $0.standings.contains { $0.team.id == 1 } })
    #expect(AppServer.beta.apiURL != AppServer.production.apiURL)
    #expect(try TournamentCode.parse("https://beta.turnie.re/t/11") == "11")
}
