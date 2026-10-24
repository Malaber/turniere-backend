import Foundation

public struct TournamentSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let code: String
    public let location: String?
    public let startsAt: String?
}

public struct Tournament: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let code: String
    public let description: String?
    public let location: String?
    public let startsAt: String?
    public let timestamp: String?
    public let timerMode: String?
    public let timerReasonText: String?
    public let playerScoreProposalsEnabled: Bool?
    public let teams: [Team]
    public let stages: [Stage]

    public var orderedStages: [Stage] {
        stages.sorted { a, b in
            func order(_ level: Int) -> Int { level == -1 ? -100 : level < -1 ? -99 : 100 - level }
            return order(a.level) == order(b.level) ? a.id < b.id : order(a.level) < order(b.level)
        }
    }
    public var matches: [Match] {
        var seen = Set<Int>()
        return orderedStages.flatMap(\.allMatches).filter { seen.insert($0.id).inserted }
    }
    public func matches(for teamID: Int) -> [Match] {
        matches.filter { $0.matchScores.contains { $0.team?.id == teamID } }
    }
    public func groups(for teamID: Int) -> [Group] {
        orderedStages.flatMap { $0.groups.sorted { $0.number < $1.number } }
            .filter { $0.groupScores.contains { $0.team.id == teamID } }
    }
    public func nextMatch(for teamID: Int) -> Match? {
        let games = matches(for: teamID)
        return games.first { $0.state == "in_progress" } ?? games.first { $0.state == "not_started" }
    }
    public var webURL: URL { URL(string: "https://turnie.re")!.appendingPathComponent("t").appendingPathComponent(String(id)) }
}

public struct Team: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
}

public struct Stage: Codable, Identifiable, Sendable {
    public let id: Int
    public let level: Int
    public let state: String
    public let matches: [Match]
    public let groups: [Group]
    public var title: String {
        if state == "intermediate_stage" { return L10n.text("stage.intermediate") }
        switch level {
        case -1: return L10n.text("stage.groups")
        case -2: return L10n.text("stage.intermediate")
        case 0: return L10n.text("stage.final")
        case 1: return L10n.text("stage.semi")
        case 2: return L10n.text("stage.quarter")
        case 3: return L10n.text("stage.last16")
        default: return L10n.format("stage.round", level)
        }
    }
    public var allMatches: [Match] {
        (matches + groups.flatMap(\.matches)).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }
}

public struct Group: Codable, Identifiable, Sendable {
    public let id: Int
    public let number: Int
    public let matches: [Match]
    public let groupScores: [Standing]
    // Ranking and ties belong to the backend. Preserve server order for equal positions.
    public var standings: [Standing] {
        groupScores.enumerated().sorted {
            ($0.element.position, $0.offset) < ($1.element.position, $1.offset)
        }.map(\.element)
    }
}

public struct Standing: Codable, Identifiable, Sendable {
    public let id: Int
    public let groupPoints: Int
    public let scoredPoints: Int
    public let receivedPoints: Int
    public let differenceInPoints: Int
    public let position: Int
    public let team: Team
}

public struct Match: Codable, Identifiable, Sendable {
    public let id: Int
    public let state: String
    public let position: Int
    public let decider: Bool
    public let location: String?
    public let startTime: String?
    public let notes: String?
    public let winner: Team?
    public let matchScores: [MatchScore]
    public var status: String {
        switch state {
        case "in_progress": return L10n.text("status.live")
        case "finished": return L10n.text("status.finished")
        case "not_started": return L10n.text("status.scheduled")
        case "single_team": return L10n.text("status.bye")
        case "not_ready": return L10n.text("status.pending")
        case "undecided": return L10n.text("status.draw")
        default: return L10n.text("status.unknown")
        }
    }
    public func points(for score: MatchScore) -> String {
        guard ["in_progress", "finished", "undecided"].contains(state) else { return "–" }
        return (decider ? score.hiddenPoints : score.points).map(String.init) ?? "–"
    }
}

public struct MatchScore: Codable, Identifiable, Sendable {
    public let id: Int
    public let points: Int?
    public let hiddenPoints: Int?
    public let team: Team?
}

public enum TournamentCode {
    public static func parse(_ input: String) throws -> String {
        var code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.contains("://") {
            guard let url = URL(string: code), url.scheme == "https", ["turnie.re", "beta.turnie.re"].contains(url.host ?? ""),
                  url.user == nil, url.password == nil,
                  url.pathComponents.count >= 3, url.pathComponents[1] == "t" else {
                throw APIError.invalidCode
            }
            code = url.pathComponents[2]
        }
        guard code.range(of: "^([a-fA-F0-9]{6}|[0-9]{1,10})$", options: .regularExpression) != nil else {
            throw APIError.invalidCode
        }
        return code.lowercased()
    }
}

public enum APIDate {
    public static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
