import SwiftUI
import SwiftData

/// Create a match or fix team names, format and toss for an existing one.
/// Player names themselves are edited in `PlayerListEditor` (fix-name support).
struct MatchSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var matchToEdit: Match? = nil

    @State private var teamA = "Team A"
    @State private var teamB = "Team B"
    @State private var title = ""
    @State private var venue = ""
    @State private var overs = 20
    @State private var playersPerSide = 11
    @State private var inningsPerTeam = 1
    @State private var tossWinner: TeamSide = .a
    @State private var tossDecision: TossDecision = .bat

    var body: some View {
        NavigationStack {
            Form {
                Section("Fixture") {
                    TextField("Match title (optional)", text: $title)
                    TextField("Venue (optional)", text: $venue)
                    TextField("Team A name", text: $teamA)
                    TextField("Team B name", text: $teamB)
                }
                Section("Format") {
                    Stepper("Overs per innings: \(overs)", value: $overs, in: 5...50)
                    Stepper("Players per side: \(playersPerSide)", value: $playersPerSide, in: 5...11)
                    Picker("Innings per team", selection: $inningsPerTeam) {
                        Text("1").tag(1); Text("2").tag(2)
                    }
                }
                Section("Toss") {
                    Picker("Toss won by", selection: $tossWinner) {
                        Text(teamA.isEmpty ? "Team A" : teamA).tag(TeamSide.a)
                        Text(teamB.isEmpty ? "Team B" : teamB).tag(TeamSide.b)
                    }
                    Picker("Elected to", selection: $tossDecision) {
                        Text("Bat").tag(TossDecision.bat)
                        Text("Bowl").tag(TossDecision.bowl)
                    }
                    Text("\(battingFirstName) will bat first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if matchToEdit == nil {
                    Section {
                        Text("You will enter player names next. Add all \(playersPerSide) per side, or score with fewer and add players as they bat or bowl.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(matchToEdit == nil ? "New Match" : "Edit Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(matchToEdit == nil ? "Create" : "Save") { save() }
                        .disabled(teamA.trimmingCharacters(in: .whitespaces).isEmpty
                                  || teamB.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var battingFirstName: String {
        let winner = tossWinner == .a ? teamA : teamB
        let other = tossWinner == .a ? teamB : teamA
        return tossDecision == .bat ? winner : other
    }

    private func loadExisting() {
        guard let m = matchToEdit else { return }
        teamA = m.teamAName; teamB = m.teamBName; title = m.title; venue = m.venue
        overs = m.oversPerInnings; playersPerSide = m.playersPerSide
        inningsPerTeam = m.inningsPerTeam
        tossWinner = m.tossWinner; tossDecision = m.tossDecision
    }

    private func save() {
        let a = teamA.trimmingCharacters(in: .whitespaces)
        let b = teamB.trimmingCharacters(in: .whitespaces)
        if let m = matchToEdit {
            m.teamAName = a; m.teamBName = b; m.title = title; m.venue = venue
            m.oversPerInnings = overs; m.playersPerSide = playersPerSide
            m.inningsPerTeam = inningsPerTeam
            m.tossWinner = tossWinner; m.tossDecision = tossDecision
        } else {
            let m = Match()
            m.teamAName = a; m.teamBName = b; m.title = title; m.venue = venue
            m.oversPerInnings = overs; m.playersPerSide = playersPerSide
            m.inningsPerTeam = inningsPerTeam
            m.tossWinner = tossWinner; m.tossDecision = tossDecision
            // Pre-create empty player slots so names can be typed quickly.
            for side in [TeamSide.a, TeamSide.b] {
                for i in 0..<playersPerSide {
                    let p = Player(name: "", side: side, battingOrder: i)
                    p.match = m; m.players.append(p); context.insert(p)
                }
            }
            context.insert(m)
            // First innings shell, ready for openers once squads are named.
            let inn = Innings(inningsNumber: 1, battingSide: m.battingFirst)
            inn.match = m; m.inningsList.append(inn); context.insert(inn)
        }
        try? context.save()
        dismiss()
    }
}

/// Add / rename / reorder players, mark captain and wicket-keeper.
/// This is the "fix the name of the player" surface used mid-match.
struct PlayerListEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match
    let side: TeamSide
    @State private var newName = ""
    @State private var duplicateWarning: String?

    private var players: [Player] { match.players(for: side) }
    private var newNameIsDuplicate: Bool {
        match.isNameTaken(newName, in: side)
    }

    var body: some View {
        List {
            Section("\(match.teamName(side)) — batting order") {
                ForEach(players) { player in
                    HStack {
                        Text("\(player.battingOrder + 1).").foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        PlayerNameField(player: player) { candidate in
                            match.isNameTaken(candidate, in: side, excluding: player.id)
                        } onRejected: { candidate in
                            duplicateWarning = "\"\(candidate)\" is already used in \(match.teamName(side)). Two players in one team cannot share a name — please use a different name or add a middle initial."
                        }
                        if player.isCaptain { Text("©").foregroundStyle(.secondary) }
                        if player.isWicketKeeper { Text("†").foregroundStyle(.secondary) }
                    }
                    .swipeActions(edge: .leading) {
                        Button { player.isCaptain.toggle(); try? context.save() } label: {
                            Label("Captain", systemImage: "c.circle") }
                        Button { player.isWicketKeeper.toggle(); try? context.save() } label: {
                            Label("Keeper", systemImage: "hand.raised") }
                    }
                }
                .onMove { from, to in
                    var ordered = players
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (i, p) in ordered.enumerated() { p.battingOrder = i }
                    try? context.save()
                }
                .onDelete { offsets in
                    offsets.map { players[$0] }.forEach(context.delete)
                    renumber(); try? context.save()
                }
            }
            Section("Quick add") {
                HStack {
                    TextField("Add player name", text: $newName)
                    Button("Add") {
                        let cleaned = newName.trimmingCharacters(in: .whitespaces)
                        guard !match.isNameTaken(cleaned, in: side) else {
                            duplicateWarning = "\"\(cleaned)\" is already used in \(match.teamName(side)). Two players in one team cannot share a name."
                            return
                        }
                        let p = Player(name: cleaned, side: side, battingOrder: players.count)
                        p.match = match; match.players.append(p); context.insert(p)
                        newName = ""; try? context.save()
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newNameIsDuplicate)
                }
                if newNameIsDuplicate {
                    Text("Name already used in this team. Two players in one team cannot share a name.")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Tip: paste a squad list one name per line in Notes, then type names here. Swipe a row to mark © captain or † keeper. Drag to set batting order.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(match.teamName(side))
        .toolbar { EditButton() }
        .alert("Name Already Used", isPresented: Binding(
            get: { duplicateWarning != nil },
            set: { if !$0 { duplicateWarning = nil } })) {
            Button("OK", role: .cancel) { duplicateWarning = nil }
        } message: {
            Text(duplicateWarning ?? "")
        }
    }
    private func renumber() {
        for (i, p) in players.enumerated() { p.battingOrder = i }
    }
}

/// Name editor that only commits non-duplicate names. A duplicate is
/// rejected on Return / focus loss and the saved name is restored.
struct PlayerNameField: View {
    @Environment(\.modelContext) private var context
    @Bindable var player: Player
    let isDuplicate: (String) -> Bool
    let onRejected: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Player name", text: $draft)
            .focused($focused)
            .onAppear { draft = player.name }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let cleaned = draft.trimmingCharacters(in: .whitespaces)
        guard cleaned != player.name else { draft = player.name; return }
        guard !isDuplicate(cleaned) else {
            onRejected(cleaned)
            draft = player.name
            return
        }
        player.name = cleaned
        draft = cleaned
        try? context.save()
    }
}
