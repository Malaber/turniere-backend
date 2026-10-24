import Foundation
import Observation
import Security
import TurniereCore

@MainActor @Observable
final class PlayerStore {
    private var tokens: PlayerTokens?
    private let api: PlayerAPI
    private let keychainService: String
    private let demo: Bool
    var matches: [Int: [PlayerMatch]] = [:]
    var busy = false
    var error: String?
    var signedIn: Bool { tokens != nil }

    init(server: AppServer) {
        api = PlayerAPI(baseURL: server.apiURL)
        keychainService = "re.turnie.player.\(server.rawValue)"
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        demo = false
        #endif
        if !demo {
            var result: CFTypeRef?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService, kSecAttrAccount as String: "session",
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                tokens = try? JSONDecoder().decode(PlayerTokens.self, from: data)
            }
        }
    }
    func signIn(email: String, password: String) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let next = demo ? PlayerTokens(accessToken: "demo", client: "demo", uid: "demo") :
                try await api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            save(next)
        } catch { failure(error, signingIn: true) }
    }
    func signOut() async {
        guard !busy else { return }; busy = true; error = nil
        let previous = tokens
        clear()
        if let previous, !demo {
            do { try await api.signOut(tokens: previous) }
            catch { self.error = L10n.text("account.signOutOffline") }
        }
        busy = false
    }
    func refresh(_ tournamentID: Int) async {
        guard !busy, let tokens else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            if demo {
                if matches[tournamentID] == nil { matches[tournamentID] = try demoMatches(locked: false) }
            } else {
                let (result, next) = try await api.matches(tournamentID: tournamentID, tokens: tokens)
                save(next); matches[tournamentID] = result.matches
            }
        } catch { failure(error) }
    }
    func submit(_ match: PlayerMatch, teamID: Int, scores: [String: String], tournamentID: Int) async {
        guard !busy, let tokens, match.accepting, match.eligibleTeamIds.contains(teamID) else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let values = try ProposalScores.validated(scores, teams: match.teams.map(\.id))
            if demo { matches[tournamentID] = try demoMatches(locked: true) }
            else {
                let (result, next) = try await api.submit(matchID: match.id, teamID: teamID, scores: values, tokens: tokens)
                save(next)
                matches[tournamentID] = matches[tournamentID]?.map { $0.id == result.id ? result : $0 }
            }
        } catch {
            failure(error)
            // A response can be lost after the server committed. Read state; never retry writes automatically.
            if !demo, let current = self.tokens,
               let (result, next) = try? await api.matches(tournamentID: tournamentID, tokens: current) {
                save(next); matches[tournamentID] = result.matches
            }
        }
    }
    private func failure(_ error: Error, signingIn: Bool = false) {
        let apiError: APIError?
        if let response = error as? PlayerHTTPError {
            if let next = response.tokens { save(next) }
            apiError = .status(response.status)
        } else { apiError = error as? APIError }
        switch apiError {
        case .status(401):
            clear(); self.error = L10n.text(signingIn ? "account.invalid" : "account.expired")
        case .status(409): self.error = L10n.text("proposal.conflict")
        case .status(403): self.error = L10n.text("proposal.forbidden")
        default: self.error = L10n.message(for: apiError ?? error)
        }
    }
    private func clear() {
        tokens = nil; matches = [:]
        if !demo { SecItemDelete(identity as CFDictionary) }
    }
    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "session"]
    }
    private func save(_ next: PlayerTokens) {
        tokens = next
        guard !demo, let data = try? JSONEncoder().encode(next) else { return }
        let status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            if SecItemAdd(item as CFDictionary, nil) != errSecSuccess { error = L10n.text("account.storage") }
        } else if status != errSecSuccess { error = L10n.text("account.storage") }
    }
    private func demoMatches(locked: Bool) throws -> [PlayerMatch] {
        let name = locked ? "demo-proposals-locked" : "demo-proposals"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw APIError.invalidResponse }
        return try APIClient.decoder().decode(PlayerMatchList.self, from: Data(contentsOf: url)).matches
    }
}
