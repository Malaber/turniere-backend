import SwiftUI
import TurniereCore

@main
struct TurniereApp: App {
    // Environment is a build choice, never a persisted user preference.
    #if TURNIERE_BETA
    private let server: AppServer = .beta
    #else
    private let server: AppServer = .production
    #endif
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            ServerRoot(server: server)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}

struct ServerRoot: View {
    @State private var store: TournamentStore
    @State private var player: PlayerStore
    init(server: AppServer) {
        _store = State(initialValue: TournamentStore(server: server))
        _player = State(initialValue: PlayerStore(server: server))
    }
    var body: some View { RootView().environment(store).environment(player) }
}

struct RootView: View {
    @Environment(PlayerStore.self) private var player
    @AppStorage("accountNudgeDismissed") private var accountNudgeDismissed = false
    @State private var account = false
    @Environment(TournamentStore.self) private var store
    @State private var path: [String] = []
    @State private var input = ""
    @State private var search = ""
    @State private var codeError: String?
    @State private var settings = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.text("home.title"), systemImage: "trophy.fill")
                                .font(.title2.bold()).foregroundStyle(.tint)
                            Text(L10n.text("home.subtitle"))
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                        TextField(L10n.text("home.code"), text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.go).onSubmit(openCode)
                            .accessibilityIdentifier("tournament-code")
                        Button(L10n.text("home.open"), systemImage: "arrow.right.circle.fill", action: openCode)
                            .accessibilityIdentifier("open-tournament")
                        if let codeError { Text(codeError).foregroundStyle(.red) }
                    }
                    if let error = store.storageError { Section { Notice(text: error) } }
                    Section(L10n.text("home.public")) {
                        if let error = store.listError {
                            Notice(text: error)
                            Button(L10n.text("action.reload")) { Task { await store.discover() } }
                        }
                        if store.loading.contains("index") && store.tournaments.isEmpty { ProgressView(L10n.text("home.loading")) }
                        ForEach(store.tournaments.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.code.contains(search.lowercased()) }) { tournament in
                            NavigationLink(value: tournament.code) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tournament.name).font(.headline)
                                    if let location = tournament.location, !location.isEmpty {
                                        Label(location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Text(tournament.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }
                        }
                        if store.tournaments.isEmpty && !store.loading.contains("index") && store.listError == nil {
                            Text(L10n.text("home.empty")).foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("turnie.re")
                .searchable(text: $search, prompt: L10n.text("home.search"))
                .navigationDestination(for: String.self) { TournamentView(code: $0) }
                .toolbar { Button(L10n.text("settings.title"), systemImage: "gearshape") { settings = true } }
                .refreshable { await store.discover() }
                .task { await store.discover() }
            }.tabItem { Label(L10n.text("tab.discover"), systemImage: "trophy") }.tag(0)

            NavigationStack {
                List {
                    if !player.signedIn && !accountNudgeDismissed {
                        Section {
                            Text(L10n.text("account.nudge.title")).font(.headline)
                            Text(L10n.text("account.nudge.body")).foregroundStyle(.secondary)
                            Button(L10n.text("account.signIn")) { account = true }
                                .accessibilityIdentifier("saved-sign-in")
                            Button(L10n.text("account.nudge.dismiss")) { accountNudgeDismissed = true }
                                .accessibilityIdentifier("dismiss-account-nudge")
                        }
                    }
                    if store.library.entries.isEmpty {
                        ContentUnavailableView(L10n.text("saved.empty.title"), systemImage: "star", description: Text(L10n.text("saved.empty.body")))
                    }
                    ForEach(store.library.entries) { entry in
                        NavigationLink { TournamentView(code: entry.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.tournament.name).font(.headline)
                                if let team = entry.tournament.teams.first(where: { $0.id == entry.favoriteTeamID }) {
                                    Label(team.name, systemImage: "star.fill").foregroundStyle(.tint)
                                }
                                Text(L10n.format("updated", entry.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.swipeActions { Button(L10n.text("action.remove"), role: .destructive) { store.remove(entry.id) } }
                    }
                }.navigationTitle(L10n.text("tab.saved"))
            }.tabItem { Label(L10n.text("tab.saved"), systemImage: "star") }.tag(1)
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $account) { AccountView(server: store.server) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reset-demo") {
                accountNudgeDismissed = false
            }
            #endif
        }
    }
    private func openCode() {
        do {
            if input.contains("://"), let host = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines))?.host,
               host != store.server.webURL.host { codeError = L10n.text("server.wrongLink"); return }
            let code = try TournamentCode.parse(input); codeError = nil; path.append(code)
        }
        catch { codeError = L10n.message(for: error) }
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.subheadline).foregroundStyle(.secondary).accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @Environment(TournamentStore.self) private var store
    @State private var account = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("settings.appearance")) {
                    Picker(L10n.text("settings.theme"), selection: $appearance) {
                        Text(L10n.text("theme.system")).tag("system"); Text(L10n.text("theme.light")).tag("light"); Text(L10n.text("theme.dark")).tag("dark")
                    }
                }
                Section(L10n.text("account.title")) {
                    Button(L10n.text("account.title")) { account = true }
                    Text(L10n.text("account.\(store.server.rawValue)"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("account-environment")
                }
                Section(L10n.text("settings.about")) {
                    Text(L10n.text("settings.local"))
                    Text(L10n.text("settings.refresh"))
                    Link(L10n.text("link.website"), destination: URL(string: "https://turnie.re")!)
                    Link(L10n.text("link.support"), destination: URL(string: "https://turnie.re/support")!)
                    Link(L10n.text("link.privacy"), destination: URL(string: "https://turnie.re/app-privacy")!)
                        .accessibilityIdentifier("privacy-link")
                    Text(L10n.format("version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")).foregroundStyle(.secondary)
                }
            }.sheet(isPresented: $account) { AccountView(server: store.server) }
                .navigationTitle(L10n.text("settings.title"))
                .toolbar { Button(L10n.text("action.done")) { dismiss() } }
        }
    }
}
