import SwiftUI
import TurniereCore

struct TournamentView: View {
    let code: String
    @Environment(TournamentStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var section = "overview"
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
                        Text(L10n.format("updated", entry.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = store.errors[code] {
                            Notice(text: L10n.format("offline", error))
                        }
                        if let error = store.storageError { Notice(text: error) }
                    }.padding(.vertical, 4)
                    Picker(L10n.text("view.label"), selection: $section) {
                        ForEach(["overview", "matches", "standings", "team"], id: \.self) { Text(L10n.text("section.\($0)")).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("detail-section")
                }
                switch section {
                case "matches": matches(entry.tournament)
                case "standings": standings(entry.tournament)
                case "team": teamSection(entry.tournament)
                default: overview(entry.tournament)
                }
            } else if let error = store.errors[code] {
                ContentUnavailableView(L10n.text("tournament.error"), systemImage: "wifi.exclamationmark", description: Text(error))
                Button(L10n.text("action.retry")) { Task { await store.refresh(code) } }
            } else { ProgressView(L10n.text("tournament.loading")) }
        }
        .navigationTitle(L10n.text("tournament.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let tournament = entry?.tournament {
                ShareLink(item: tournament.webURL)
                Button(L10n.text("favorite.choose"), systemImage: favorite == nil ? "star" : "star.fill") { choosingTeam = true }
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
        Section(L10n.text("favorite.title")) {
            if let team = tournament.teams.first(where: { $0.id == favorite }) {
                Label(team.name, systemImage: "star.fill").font(.headline).foregroundStyle(.tint)
                if let match = tournament.nextMatch(for: team.id) {
                    Text(match.state == "in_progress" ? L10n.text("match.now") : L10n.text("match.next")).font(.subheadline).foregroundStyle(.secondary)
                    MatchRow(match: match, favorite: favorite)
                } else { Text(L10n.text("match.noNext")).foregroundStyle(.secondary) }
                Button(L10n.text("team.allMatches")) { section = "team" }
            } else {
                Button(L10n.text("favorite.choose"), systemImage: "star") { choosingTeam = true }
                Text(L10n.text("favorite.hint")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        if let end = APIDate.parse(tournament.timestamp) {
            Section(L10n.text("timer.title")) {
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
        if !live.isEmpty { Section(L10n.text("matches.live")) { ForEach(live) { MatchRow(match: $0, favorite: favorite) } } }
        Section(L10n.text("tournament.info")) {
            LabeledContent(L10n.text("tournament.teams"), value: String(tournament.teams.count))
            LabeledContent(L10n.text("section.matches"), value: String(tournament.matches.count))
            if let date = APIDate.parse(tournament.startsAt) { LabeledContent(L10n.text("tournament.start"), value: date.formatted(date: .abbreviated, time: .shortened)) }
            if let description = tournament.description, !description.isEmpty { Text(description) }
            Link(L10n.text("link.browser"), destination: tournament.webURL)
        }
    }
    @ViewBuilder private func matches(_ tournament: Tournament) -> some View {
        if tournament.matches.isEmpty { Text(L10n.text("matches.empty")).foregroundStyle(.secondary) }
        ForEach(tournament.orderedStages) { stage in
            if !stage.matches.isEmpty {
                Section(stage.title) { ForEach(stage.matches.sorted { ($0.position, $0.id) < ($1.position, $1.id) }) { MatchRow(match: $0, favorite: favorite) } }
            }
            ForEach(stage.groups.sorted { $0.number < $1.number }) { group in
                Section(L10n.format("stage.group", stage.title, group.number)) {
                    ForEach(group.matches.sorted { ($0.position, $0.id) < ($1.position, $1.id) }) { MatchRow(match: $0, favorite: favorite) }
                }
            }
        }
    }
    @ViewBuilder private func standings(_ tournament: Tournament) -> some View {
        if tournament.stages.allSatisfy({ $0.groups.isEmpty }) {
            ContentUnavailableView(L10n.text("standings.empty.title"), systemImage: "list.number", description: Text(L10n.text("standings.empty.body")))
        }
        ForEach(tournament.orderedStages) { stage in
            ForEach(stage.groups.sorted { $0.number < $1.number }) { group in
                Section(L10n.format("stage.group", stage.title, group.number)) {
                    ForEach(group.standings) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.position > 0 ? String(row.position) : "–").font(.headline.monospacedDigit()).frame(minWidth: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.team.name).font(.headline)
                                Text(L10n.format("standings.score", row.scoredPoints, row.receivedPoints, row.differenceInPoints)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if row.team.id == favorite { Image(systemName: "star.fill").foregroundStyle(.tint).accessibilityLabel(L10n.text("favorite.label")) }
                            Text(L10n.format("standings.points", row.groupPoints)).font(.headline.monospacedDigit())
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    @ViewBuilder private func teamSection(_ tournament: Tournament) -> some View {
        if let team = tournament.teams.first(where: { $0.id == favorite }) {
            Section { Label(team.name, systemImage: "star.fill").font(.title2.bold()); Button(L10n.text("team.change")) { choosingTeam = true } }
            let games = tournament.matches(for: team.id)
            if games.isEmpty { Text(L10n.text("team.empty")) }
            Section(L10n.text("team.matches")) { ForEach(games) { MatchRow(match: $0, favorite: favorite) } }
        } else {
            Section { Text(L10n.text("team.chooseHint")); Button(L10n.text("favorite.choose")) { choosingTeam = true } }
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
                Text(match.decider ? L10n.text("match.decider") : L10n.format("match.number", match.position + 1))
            }.font(.caption)
            ForEach(match.matchScores) { score in
                HStack(alignment: .firstTextBaseline) {
                    if let id = score.team?.id, id == favorite { Image(systemName: "star.fill").foregroundStyle(.tint).accessibilityLabel(L10n.text("favorite.label")) }
                    Text(score.team?.name ?? L10n.text("team.pending")).fontWeight(score.team?.id == match.winner?.id ? .bold : .regular)
                    Spacer(minLength: 12)
                    Text(match.points(for: score)).font(.title3.bold().monospacedDigit())
                }
            }
            if match.matchScores.count < 2 { Text(match.state == "single_team" ? L10n.text("match.bye") : L10n.text("match.opponentPending")).foregroundStyle(.secondary) }
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
                Button(L10n.text("favorite.none")) { choose(nil); dismiss() }
                ForEach(tournament.teams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { team in
                    Button { choose(team.id); dismiss() } label: {
                        HStack { Text(team.name); Spacer(); if team.id == selected { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("team-\(team.id)")
                }
            }.searchable(text: $search, prompt: L10n.text("team.search"))
                .navigationTitle(L10n.text("favorite.label"))
                .toolbar { Button(L10n.text("action.done")) { dismiss() } }
        }
    }
}
