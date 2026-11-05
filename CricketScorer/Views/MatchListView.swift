import SwiftUI
import SwiftData

struct MatchListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Match.createdAt, order: .reverse) private var matches: [Match]
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if matches.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches Yet", systemImage: "sportscourt")
                    } description: {
                        Text("Create a match, enter both teams, record the toss, and score ball by ball. Everything stays on this device.")
                    } actions: {
                        Button("New Match") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(matches) { match in
                            NavigationLink(value: match) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.title.isEmpty
                                         ? "\(match.teamAName) v \(match.teamBName)" : match.title)
                                        .font(.headline)
                                    Text("\(match.teamAName) v \(match.teamBName) • \(match.oversPerInnings) overs • \(match.status.rawValue.capitalized)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(match.matchDate, style: .date)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { matches[$0] }.forEach(context.delete)
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Cricket Scorer")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreate = true } label: { Label("New Match", systemImage: "plus") }
                }
            }
            .navigationDestination(for: Match.self) { match in
                MatchHubView(match: match)
            }
            .sheet(isPresented: $showingCreate) { MatchSetupView() }
        }
    }
}

/// Hub for one match: continue scoring, view scorecard, or fix details.
struct MatchHubView: View {
    @Bindable var match: Match
    var body: some View {
        List {
            Section("Match") {
                LabeledContent("Fixture", value: "\(match.teamAName) v \(match.teamBName)")
                LabeledContent("Toss", value: "\(match.teamName(match.tossWinner)) won, elected to \(match.tossDecision.rawValue)")
                LabeledContent("Format", value: "\(match.oversPerInnings) overs • \(match.playersPerSide)-a-side")
                LabeledContent("Status", value: match.status.rawValue.capitalized)
            }
            Section {
                NavigationLink {
                    LiveScoringView(match: match)
                } label: { Label(match.status == .setup ? "Start Scoring" : "Continue Scoring", systemImage: "play.circle") }
                NavigationLink {
                    ScorecardView(match: match)
                } label: { Label("Scorecard & Ball-by-Ball", systemImage: "list.bullet.rectangle") }
                NavigationLink {
                    MatchSetupView(matchToEdit: match)
                } label: { Label("Edit Teams, Players & Toss", systemImage: "person.3") }
            }
            Section("Squads") {
                ForEach([TeamSide.a, TeamSide.b]) { side in
                    NavigationLink {
                        PlayerListEditor(match: match, side: side)
                    } label: {
                        LabeledContent(match.teamName(side),
                                       value: "\(match.players(for: side).count) players")
                    }
                }
            }
        }
        .navigationTitle(match.title.isEmpty ? "Match" : match.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension TeamSide: Identifiable { public var id: String { rawValue } }
