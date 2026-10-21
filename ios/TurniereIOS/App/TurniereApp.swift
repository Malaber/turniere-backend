import SwiftUI
import TurniereCore

@main
struct TurniereApp: App {
    @State private var store = TournamentStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}

struct RootView: View {
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
                            Label("Dein Turnier. Dein Team.", systemImage: "trophy.fill")
                                .font(.title2.bold()).foregroundStyle(.tint)
                            Text("Spielplan, Ergebnisse und dein Lieblingsteam immer dabei.")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                        TextField("Turniercode oder Link", text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.go).onSubmit(openCode)
                            .accessibilityIdentifier("tournament-code")
                        Button("Turnier öffnen", systemImage: "arrow.right.circle.fill", action: openCode)
                            .accessibilityIdentifier("open-tournament")
                        if let codeError { Text(codeError).foregroundStyle(.red) }
                    }
                    if let error = store.storageError { Section { Notice(text: error) } }
                    Section("Öffentliche Turniere") {
                        if let error = store.listError {
                            Notice(text: error)
                            Button("Erneut laden") { Task { await store.discover() } }
                        }
                        if store.loading.contains("index") && store.tournaments.isEmpty { ProgressView("Turniere laden …") }
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
                            Text("Noch keine öffentlichen Turniere. Öffne ein Turnier mit seinem Code.").foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("turnie.re")
                .searchable(text: $search, prompt: "Turniere suchen")
                .navigationDestination(for: String.self) { TournamentView(code: $0) }
                .toolbar { Button("Einstellungen", systemImage: "gearshape") { settings = true } }
                .refreshable { await store.discover() }
                .task { await store.discover() }
            }.tabItem { Label("Entdecken", systemImage: "trophy") }.tag(0)

            NavigationStack {
                List {
                    if store.library.entries.isEmpty {
                        ContentUnavailableView("Noch kein Turnier", systemImage: "star", description: Text("Öffne ein Turnier unter Entdecken. Es bleibt hier verfügbar, auch ohne Verbindung."))
                    }
                    ForEach(store.library.entries) { entry in
                        NavigationLink { TournamentView(code: entry.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.tournament.name).font(.headline)
                                if let team = entry.tournament.teams.first(where: { $0.id == entry.favoriteTeamID }) {
                                    Label(team.name, systemImage: "star.fill").foregroundStyle(.tint)
                                }
                                Text("Stand: \(entry.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.swipeActions { Button("Entfernen", role: .destructive) { store.remove(entry.id) } }
                    }
                }.navigationTitle("Meine Turniere")
            }.tabItem { Label("Meine Turniere", systemImage: "star") }.tag(1)
        }
        .sheet(isPresented: $settings) { SettingsView() }
    }
    private func openCode() {
        do { let code = try TournamentCode.parse(input); codeError = nil; path.append(code) }
        catch { codeError = error.localizedDescription }
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section("Darstellung") {
                    Picker("Design", selection: $appearance) {
                        Text("System").tag("system"); Text("Hell").tag("light"); Text("Dunkel").tag("dark")
                    }
                }
                Section("Über turnie.re") {
                    Text("Turniere verfolgen und dein Lieblingsteam merken. Die Auswahl bleibt auf diesem Gerät.")
                    Text("Ergebnisse werden während der Nutzung alle 20 Sekunden aktualisiert. Ohne Verbindung siehst du den zuletzt geladenen Stand.")
                    Link("turnie.re besuchen", destination: URL(string: "https://turnie.re")!)
                    Text("Version 0.1.0").foregroundStyle(.secondary)
                }
            }.navigationTitle("Einstellungen")
                .toolbar { Button("Fertig") { dismiss() } }
        }
    }
}
