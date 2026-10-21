import SwiftUI
import TurniereCore

struct TournamentView: View {
    let code: String
    @Environment(TournamentStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var section = "Überblick"
    @State private var choosingTeam = false
    private var entry: SavedTournament? { store.entry(code) }
    private var favorite: Int? { entry?.favoriteTeamID }

    var body: some View {
        List {
            if let entry {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.tournament.name).font(.title2.bold())
                        if let location = entry.tournament.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                        }
                        Text("Stand: \(entry.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = store.errors[code] {
                            Notice(text: "Aktualisierung fehlgeschlagen. Gespeicherter Stand wird angezeigt. \(error)")
                        }
                        if let error = store.storageError { Notice(text: error) }
                    }.padding(.vertical, 4)
                    Picker("Ansicht", selection: $section) {
                        ForEach(["Überblick", "Spiele", "Tabelle", "Mein Team"], id: \.self) { Text($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("detail-section")
                }
                switch section {
                case "Spiele": matches(entry.tournament)
                case "Tabelle": standings(entry.tournament)
                case "Mein Team": teamSection(entry.tournament)
                default: overview(entry.tournament)
                }
            } else if let error = store.errors[code] {
                ContentUnavailableView("Turnier nicht geladen", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Erneut versuchen") { Task { await store.refresh(code) } }
            } else { ProgressView("Turnier laden …") }
        }
        .navigationTitle("Turnier").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let tournament = entry?.tournament {
                ShareLink(item: tournament.webURL)
                Button("Lieblingsteam wählen", systemImage: favorite == nil ? "star" : "star.fill") { choosingTeam = true }
                    .accessibilityIdentifier("choose-team")
            }
        }
        .sheet(isPresented: $choosingTeam) {
            if let tournament = entry?.tournament { TeamPicker(tournament: tournament, selected: favorite) { store.favorite($0, in: code) } }
        }
        .refreshable { await store.refresh(code) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            repeat {
                await store.refresh(code)
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            } while !Task.isCancelled
        }
    }
    @ViewBuilder private func overview(_ tournament: Tournament) -> some View {
        Section("Dein Lieblingsteam") {
            if let team = tournament.teams.first(where: { $0.id == favorite }) {
                Label(team.name, systemImage: "star.fill").font(.headline).foregroundStyle(.tint)
                if let match = tournament.nextMatch(for: team.id) {
                    Text(match.state == "in_progress" ? "Jetzt auf dem Feld" : "Nächstes Spiel").font(.subheadline).foregroundStyle(.secondary)
                    MatchRow(match: match, favorite: favorite)
                } else { Text("Kein weiteres Spiel angesetzt.").foregroundStyle(.secondary) }
                Button("Alle Teamspiele") { section = "Mein Team" }
            } else {
                Button("Lieblingsteam wählen", systemImage: "star") { choosingTeam = true }
                Text("Dein Team und sein nächstes Spiel stehen dann hier.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        if let end = APIDate.parse(tournament.timestamp) {
            Section("Turnier-Timer") {
                if let reason = tournament.timerReasonText, !reason.isEmpty { Text(reason) }
                if tournament.timerMode == "countup" {
                    Text(end, style: .timer).font(.title.monospacedDigit())
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(end > context.date ? Duration.seconds(end.timeIntervalSince(context.date)).formatted(.time(pattern: .minuteSecond)) : "00:00")
                            .font(.title.monospacedDigit())
                    }
                }
            }
        }
        let live = tournament.matches.filter { $0.state == "in_progress" }
        if !live.isEmpty { Section("Laufende Spiele") { ForEach(live) { MatchRow(match: $0, favorite: favorite) } } }
        Section("Turnierinfo") {
            LabeledContent("Teams", value: String(tournament.teams.count))
            LabeledContent("Spiele", value: String(tournament.matches.count))
            if let date = APIDate.parse(tournament.startsAt) { LabeledContent("Beginn", value: date.formatted(date: .abbreviated, time: .shortened)) }
            if let description = tournament.description, !description.isEmpty { Text(description) }
            Link("Im Browser öffnen", destination: tournament.webURL)
        }
    }
    @ViewBuilder private func matches(_ tournament: Tournament) -> some View {
        if tournament.matches.isEmpty { Text("Noch keine Spiele angesetzt.").foregroundStyle(.secondary) }
        ForEach(tournament.orderedStages) { stage in
            if !stage.matches.isEmpty {
                Section(stage.title) { ForEach(stage.matches.sorted { ($0.position, $0.id) < ($1.position, $1.id) }) { MatchRow(match: $0, favorite: favorite) } }
            }
            ForEach(stage.groups.sorted { $0.number < $1.number }) { group in
                Section("\(stage.title) · Gruppe \(group.number)") {
                    ForEach(group.matches.sorted { ($0.position, $0.id) < ($1.position, $1.id) }) { MatchRow(match: $0, favorite: favorite) }
                }
            }
        }
    }
    @ViewBuilder private func standings(_ tournament: Tournament) -> some View {
        if tournament.stages.allSatisfy({ $0.groups.isEmpty }) {
            ContentUnavailableView("Keine Gruppentabelle", systemImage: "list.number", description: Text("Dieses Turnier hat keine Gruppenphase. Ergebnisse findest du unter Spiele."))
        }
        ForEach(tournament.orderedStages) { stage in
            ForEach(stage.groups.sorted { $0.number < $1.number }) { group in
                Section("\(stage.title) · Gruppe \(group.number)") {
                    ForEach(group.standings) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.position > 0 ? String(row.position) : "–").font(.headline.monospacedDigit()).frame(minWidth: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.team.name).font(.headline)
                                Text("\(row.scoredPoints):\(row.receivedPoints) · Differenz \(row.differenceInPoints)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if row.team.id == favorite { Image(systemName: "star.fill").foregroundStyle(.tint).accessibilityLabel("Lieblingsteam") }
                            Text("\(row.groupPoints) Pkt.").font(.headline.monospacedDigit())
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    @ViewBuilder private func teamSection(_ tournament: Tournament) -> some View {
        if let team = tournament.teams.first(where: { $0.id == favorite }) {
            Section { Label(team.name, systemImage: "star.fill").font(.title2.bold()); Button("Team wechseln") { choosingTeam = true } }
            let games = tournament.matches(for: team.id)
            if games.isEmpty { Text("Noch keine Spiele für dieses Team.") }
            Section("Teamspiele") { ForEach(games) { MatchRow(match: $0, favorite: favorite) } }
        } else {
            Section { Text("Wähle dein Team, um seine Spiele zu verfolgen."); Button("Lieblingsteam wählen") { choosingTeam = true } }
        }
    }
}

struct MatchRow: View {
    let match: Match
    let favorite: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(match.status, systemImage: match.state == "in_progress" ? "dot.radiowaves.left.and.right" : "sportscourt")
                    .foregroundStyle(match.state == "in_progress" ? Color.accentColor : .secondary)
                Spacer()
                Text(match.decider ? "Entscheidungsspiel" : "Spiel \(match.position + 1)")
            }.font(.caption)
            ForEach(match.matchScores) { score in
                HStack(alignment: .firstTextBaseline) {
                    if let id = score.team?.id, id == favorite { Image(systemName: "star.fill").foregroundStyle(.tint).accessibilityLabel("Lieblingsteam") }
                    Text(score.team?.name ?? "Team noch offen").fontWeight(score.team?.id == match.winner?.id ? .bold : .regular)
                    Spacer(minLength: 12)
                    Text(match.points(for: score)).font(.title3.bold().monospacedDigit())
                }
            }
            if match.matchScores.count < 2 { Text(match.state == "single_team" ? "Ohne Gegner weiter" : "Gegner noch offen").foregroundStyle(.secondary) }
            if let location = match.location, !location.isEmpty { Label(location, systemImage: "mappin").font(.caption) }
            if let date = APIDate.parse(match.startTime) { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption) }
            if let notes = match.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct TeamPicker: View {
    let tournament: Tournament
    let selected: Int?
    let choose: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Button("Kein Lieblingsteam") { choose(nil); dismiss() }
                ForEach(tournament.teams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { team in
                    Button { choose(team.id); dismiss() } label: {
                        HStack { Text(team.name); Spacer(); if team.id == selected { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("team-\(team.id)")
                }
            }.searchable(text: $search, prompt: "Team suchen")
                .navigationTitle("Lieblingsteam")
                .toolbar { Button("Fertig") { dismiss() } }
        }
    }
}
