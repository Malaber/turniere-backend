import Foundation

public struct SavedTournament: Codable, Identifiable, Sendable {
    public var id: String { tournament.code }
    public let tournament: Tournament
    public let fetchedAt: Date
    public var favoriteTeamID: Int?
    public init(tournament: Tournament, fetchedAt: Date = Date(), favoriteTeamID: Int? = nil) {
        self.tournament = tournament
        self.fetchedAt = fetchedAt
        self.favoriteTeamID = favoriteTeamID
    }
}

public struct TournamentLibrary: Codable, Sendable {
    public private(set) var entries: [SavedTournament] = []
    public init() {}
    public mutating func update(_ tournament: Tournament, at date: Date = Date()) {
        let favorite = entries.first { $0.id == tournament.code }?.favoriteTeamID
        entries.removeAll { $0.id == tournament.code }
        entries.insert(SavedTournament(tournament: tournament, fetchedAt: date, favoriteTeamID: favorite), at: 0)
    }
    public mutating func favorite(_ teamID: Int?, in code: String) {
        guard let index = entries.firstIndex(where: { $0.id == code }) else { return }
        guard teamID == nil || entries[index].tournament.teams.contains(where: { $0.id == teamID }) else { return }
        entries[index].favoriteTeamID = teamID
    }
    public mutating func remove(_ code: String) { entries.removeAll { $0.id == code } }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
