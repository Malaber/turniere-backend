import SwiftUI
import TurniereCore

struct AccountView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss
    let server: AppServer
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text("account.\(server.rawValue)"))
                    if player.signedIn {
                        Text(L10n.text("account.signedIn"))
                        Button(L10n.text("account.signOut"), role: .destructive) { Task { await player.signOut() } }
                    } else {
                        TextField(L10n.text("account.email"), text: $email)
                            .keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("account-email")
                        SecureField(L10n.text("account.password"), text: $password).textContentType(.password)
                            .accessibilityIdentifier("account-password")
                        Button(L10n.text("account.signIn")) {
                            Task { await player.signIn(email: email, password: password); password = ""; if player.signedIn { dismiss() } }
                        }.disabled(email.isEmpty || password.isEmpty)
                            .accessibilityIdentifier("account-sign-in")
                        Text(L10n.text("account.existing")).font(.footnote).foregroundStyle(.secondary)
                    }
                }.disabled(player.busy)
                if player.busy { ProgressView() }
                if let error = player.error { Notice(text: error) }
            }.navigationTitle(L10n.text("account.title"))
                .toolbar { Button(L10n.text("action.done")) { dismiss() } }
        }
    }
}

struct PlayerProposalsView: View {
    let tournamentID: Int
    let server: AppServer
    @Environment(PlayerStore.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = false
    var body: some View {
        List {
            Section {
                Text(L10n.text("proposal.explanation"))
                Text(L10n.text("account.\(server.rawValue)")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text(player.signedIn ? "account.title" : "account.signIn")) { account = true }
            }
            if let error = player.error { Notice(text: error).accessibilityIdentifier("proposal-error") }
            if player.signedIn {
                if let matches = player.matches[tournamentID] {
                    if matches.isEmpty { Text(L10n.text("proposal.empty")) }
                    ForEach(matches) { match in ProposalForm(match: match, tournamentID: tournamentID) }
                } else if player.busy { ProgressView() }
                Button(L10n.text("action.reload")) { Task { await player.refresh(tournamentID) } }.disabled(player.busy)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L10n.text("proposal.title"))
        .sheet(isPresented: $account) { AccountView(server: server) }
        .refreshable { await player.refresh(tournamentID) }
        .task(id: "\(player.signedIn)-\(scenePhase == .active)") {
            guard player.signedIn, scenePhase == .active else { return }
            repeat {
                await player.refresh(tournamentID)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while !Task.isCancelled
        }
    }
}

private struct ProposalForm: View {
    let match: PlayerMatch
    let tournamentID: Int
    @Environment(PlayerStore.self) private var player
    @State private var teamID = 0
    @State private var scores: [String: String] = [:]
    var body: some View {
        Section(match.teams.map(\.name).joined(separator: " – ")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("proposal.official")).font(.headline)
                ForEach(match.teams) { team in
                    LabeledContent(team.name, value: (match.officialScores[String(team.id)] ?? nil).map(String.init) ?? "–")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("proposal-official-\(team.id)")
                        .accessibilityValue((match.officialScores[String(team.id)] ?? nil).map(String.init) ?? "–")
                }
            }
            ForEach(match.teams) { team in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("proposal.from", team.name)).font(.subheadline.bold())
                    if let proposal = match.proposals.first(where: { $0.teamId == team.id }) {
                        Text(match.teams.map { "\($0.name): \(proposal.scores[String($0.id)].map(String.init) ?? "–")" }.joined(separator: " · "))
                    } else { Text(L10n.text("proposal.pending")).foregroundStyle(.secondary) }
                }
            }
            if match.locked {
                Label(L10n.text("proposal.locked"), systemImage: "lock.fill").accessibilityIdentifier("proposal-locked")
            } else if !match.accepting {
                Text(L10n.text("proposal.closed"))
            } else {
                Picker(L10n.text("proposal.team"), selection: $teamID) {
                    ForEach(match.teams.filter { match.eligibleTeamIds.contains($0.id) }) { Text($0.name).tag($0.id) }
                }
                ForEach(match.teams) { team in
                    HStack {
                        Text(team.name)
                        Spacer()
                        TextField(L10n.text("proposal.points"), text: Binding(get: { scores[String(team.id)] ?? "" }, set: { scores[String(team.id)] = $0 }))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                            .accessibilityLabel(L10n.format("proposal.pointsFor", team.name))
                            .accessibilityIdentifier("proposal-score-\(team.id)")
                    }
                }
                Button(L10n.text("proposal.submit")) {
                    Task { await player.submit(match, teamID: teamID, scores: scores, tournamentID: tournamentID) }
                }.accessibilityIdentifier("proposal-submit")
                    .disabled(!match.eligibleTeamIds.contains(teamID) || (try? ProposalScores.validated(scores, teams: match.teams.map(\.id))) == nil)
            }
        }.disabled(player.busy)
            .onAppear { teamID = match.eligibleTeamIds.first ?? 0 }
            .onChange(of: match.eligibleTeamIds) { _, ids in if !ids.contains(teamID) { teamID = ids.first ?? 0 } }
    }
}
