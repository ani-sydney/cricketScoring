import SwiftUI
import SwiftData

/// Ball-by-ball scorer (PlayHQ-style): score header, striker/non-striker,
/// current bowler, run pad, Extras / Wicket flows, Undo, Swap, Edit Ball.
struct LiveScoringView: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match
    @State private var selectedInningsID: UUID?
    @State private var pendingEvent: BallEventData?
    @State private var showExtras = false
    @State private var showWicket = false
    @State private var showBowlerPicker = false
    @State private var showOpeners = false
    @State private var editingEvent: BallEventData?
    @State private var confirmEndInnings = false
    @State private var showScorecard = false

    private var innings: Innings? {
        if let id = selectedInningsID, let f = match.inningsList.first(where: { $0.id == id }) { return f }
        return match.inningsList.sorted { $0.inningsNumber < $1.inningsNumber }.last
    }
    private var names: [UUID: String] { Dictionary(uniqueKeysWithValues: match.players.map { ($0.id, $0.name.isEmpty ? "Player \($0.battingOrder + 1)" : $0.name) }) }
    private func name(_ id: UUID?) -> String { id.flatMap { names[$0] } ?? "— Select —" }
    private var state: InningsState {
        guard let inn = innings else { return InningsState() }
        return ScoringEngine.replay(events: inn.events, playersPerSide: match.playersPerSide,
                                    oversPerInnings: match.oversPerInnings,
                                    ballsPerOver: match.ballsPerOver, names: names)
    }
    private var battingPlayers: [Player] { innings.map { match.players(for: $0.battingSide) } ?? [] }
    private var bowlingPlayers: [Player] { innings.map { match.players(for: $0.battingSide.other) } ?? [] }
    private var events: [BallEventData] { innings?.events.sorted { $0.sequence < $1.sequence } ?? [] }
    private var needsBatter: Bool { innings != nil && !state.isComplete && (state.strikerID == nil || state.nonStrikerID == nil) && !events.isEmpty }
    private var needsOpeners: Bool { innings != nil && events.isEmpty }
    // Note: end-of-over bowler prompt is handled in `append(_:)` after replay,
    // so no separate needsBowler check is required here.

    var body: some View {
        Group {
            if innings == nil {
                ContentUnavailableView("No Innings", systemImage: "sportscourt",
                    description: Text("Create the match from the hub, then start scoring."))
            } else {
                scorerBody
            }
        }
        .navigationTitle("Live Scoring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScorecard = true } label: {
                    Label("Scorecard", systemImage: "list.bullet.rectangle")
                }
                .accessibilityLabel("Show scorecard")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { undoLast() } label: { Label("Undo Last Ball", systemImage: "arrow.uturn.backward") }
                        .disabled(events.isEmpty)
                    Button { addSwapMarker() } label: { Label("Swap Striker", systemImage: "arrow.left.arrow.right") }
                    Button(role: .destructive) { confirmEndInnings = true } label: {
                        Label("End Innings", systemImage: "flag.checkered") }
                    if canStartNextInnings {
                        Button { startNextInnings() } label: {
                            Label("Start Next Innings", systemImage: "plus.circle") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("End this innings?", isPresented: $confirmEndInnings) {
            Button("Cancel", role: .cancel) {}
            Button("End Innings", role: .destructive) { endInnings() }
        } message: { Text("The innings will be marked complete. You can still edit balls afterwards from the scorecard.") }
        .sheet(isPresented: $showScorecard) {
            NavigationStack {
                ScorecardView(match: match)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showScorecard = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExtras) { extrasSheet }
        .sheet(isPresented: $showWicket) { wicketSheet }
        .sheet(isPresented: $showBowlerPicker) { bowlerSheet }
        .sheet(isPresented: $showOpeners) { openersSheet }
        .sheet(item: $editingEvent) { ev in ballEditorSheet(ev) }
        .onAppear {
            if selectedInningsID == nil { selectedInningsID = innings?.id }
            if needsOpeners { showOpeners = true }
        }
    }

    private var canStartNextInnings: Bool {
        guard let inn = innings, inn.isCompleted else { return false }
        let total = match.inningsPerTeam * 2
        return inn.inningsNumber < total
    }

    private var scorerBody: some View {
        ScrollView {
            VStack(spacing: 14) {
                inningsPicker
                scoreHeader
                battersCard
                bowlerCard
                thisOverStrip
                if state.isComplete {
                    Label(innings?.declared == true ? "Innings declared closed." : "Innings complete.", systemImage: "checkmark.seal")
                        .font(.headline)
                    if canStartNextInnings {
                        Button("Start Next Innings") { startNextInnings() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if needsOpeners {
                    Button("Select Opening Batters & Bowler") { showOpeners = true }
                        .buttonStyle(.borderedProminent)
                } else if needsBatter {
                    nextBatterPicker
                } else {
                    runPad
                }
                ballList
            }
            .padding()
        }
    }

    private var inningsPicker: some View {
        Picker("Innings", selection: Binding(
            get: { selectedInningsID ?? innings?.id ?? UUID() },
            set: { selectedInningsID = $0 })) {
            ForEach(match.inningsList.sorted { $0.inningsNumber < $1.inningsNumber }) { inn in
                Text("Inn \(inn.inningsNumber): \(match.teamName(inn.battingSide))").tag(inn.id)
            }
        }.pickerStyle(.segmented)
    }

    private var scoreHeader: some View {
        VStack(spacing: 3) {
            HStack {
                Image(systemName: "sportscourt.fill").foregroundStyle(CricketTheme.stumpGold)
                Text(match.teamName(innings?.battingSide ?? TeamSide.a))
                    .font(.headline).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if state.isComplete {
                    Label("Closed", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Label("Live", systemImage: "record.circle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.9))
                }
            }
            Text("\(state.totalRuns)/\(state.wickets)")
                .font(.system(size: 47, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).monospacedDigit()
            Text("Overs \(state.oversText) / \(match.oversPerInnings)  •  CRR \(runRate, specifier: "%.2f")\(targetText)")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            if let inn = innings, inn.inningsNumber > 1, let target = targetRuns {
                Text("Target \(target)").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(CricketTheme.pitchGreen, in: RoundedRectangle(cornerRadius: 16))
    }
    private var runRate: Double { state.legalBalls > 0 ? Double(state.totalRuns) / (Double(state.legalBalls) / Double(match.ballsPerOver)) : 0 }
    private var targetRuns: Int? {
        guard let inn = innings, inn.inningsNumber > 1 else { return nil }
        let prior = match.inningsList.filter { $0.inningsNumber < inn.inningsNumber }
        guard prior.count == inn.inningsNumber - 1 else { return nil }
        // Only a simple chase target for 2-innings matches; otherwise nil.
        return nil
    }
    private var targetText: String { "" }

    private var battersCard: some View {
        VStack(spacing: 6) {
            batterRow(id: state.strikerID, onStrike: true)
            batterRow(id: state.nonStrikerID, onStrike: false)
            Button { addSwapMarker() } label: {
                Label("Swap Striker", systemImage: "arrow.up.arrow.down").font(.caption)
            }.disabled(state.strikerID == nil)
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    private func batterRow(id: UUID?, onStrike: Bool) -> some View {
        let f = id.flatMap { state.batterFigures[$0] }
        return HStack {
            Text((onStrike ? "* " : "") + name(id)).fontWeight(onStrike ? .semibold : .regular)
            Spacer()
            Text("\(f?.runs ?? 0) (\(f?.balls ?? 0))").monospacedDigit()
        }
    }

    private var bowlerCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Bowler").font(.caption).foregroundStyle(.secondary)
                Text(name(state.currentBowlerID)).fontWeight(.semibold)
                if let id = state.currentBowlerID, let f = state.bowlerFigures[id] {
                    Text("\(f.oversText)-\(f.wickets)/\(f.runs)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Change") { showBowlerPicker = true }
                .disabled(state.isComplete)
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var thisOverStrip: some View {
        let balls = currentOverBalls
        return HStack {
            Text("This over").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if balls.isEmpty { Text("—").foregroundStyle(.secondary) }
            ForEach(balls) { e in
                Text(e.symbol).font(.caption.bold()).padding(6)
                    .background(e.isWicket ? Color.red.opacity(0.85) : Color.secondary.opacity(0.18),
                                in: Circle())
                    .foregroundStyle(e.isWicket ? .white : .primary)
            }
        }.padding(.horizontal)
    }
    private var currentOverBalls: [BallEventData] {
        let legalTarget = state.legalBalls % match.ballsPerOver
        var out: [BallEventData] = []
        var legal = 0
        for e in events.reversed() {
            if legal >= (legalTarget == 0 && state.legalBalls > 0 ? match.ballsPerOver : legalTarget) && !out.isEmpty { break }
            if e.isSwapMarker { continue }
            out.append(e)
            if e.isLegal { legal += 1 }
            if legalTarget == 0 && legal >= match.ballsPerOver { break }
        }
        return out.reversed()
    }

    private var runPad: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach([0, 1, 2, 3, 4, 6], id: \.self) { r in
                    Button("\(r)") { recordRuns(r) }
                        .buttonStyle(ScorePadButtonStyle())
                }
                Button("5 / 7+") { recordRuns(5) }.buttonStyle(ScorePadButtonStyle())
                Button("Extras") { pendingEvent = baseEvent(); showExtras = true }
                    .buttonStyle(ScorePadButtonStyle(tint: .orange))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                Button("Wicket") { pendingEvent = baseEvent(); showWicket = true }
                    .buttonStyle(ScorePadButtonStyle(tint: .red))
                Button("Undo") { undoLast() }.buttonStyle(ScorePadButtonStyle())
                    .disabled(events.isEmpty)
                Button("Bowler") { showBowlerPicker = true }.buttonStyle(ScorePadButtonStyle())
            }
            Text("Tap a ball below to fix it. Undo removes the last event. Swap corrects the striker without a ball.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var nextBatterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strikerID == nil ? "Next batter (striker end)" : "Next batter (non-striker end)")
                .font(.headline)
            ForEach(ScoringEngine.nextBatterCandidates(innings: innings!, state: state, battingPlayers: battingPlayers)) { p in
                Button(p.name.isEmpty ? "Player \(p.battingOrder + 1)" : p.name) {
                    bringInBatter(p)
                }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var ballList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ball-by-Ball (tap to fix)").font(.headline)
            ForEach(events.reversed().prefix(60)) { e in
                Button { editingEvent = e } label: {
                    HStack {
                        Text(e.symbol).bold().frame(width: 44)
                        Text("\(name(e.strikerID)) • \(e.dismissal?.label ?? (e.extra == .none ? "\(e.runsOffBat) run(s)" : e.extra.label))")
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
                Divider()
            }
            if events.isEmpty { Text("No balls yet.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: - Sheets

    private var extrasSheet: some View {
        ExtrasSheet { extra, ran, bat in
            var e = pendingEvent ?? baseEvent()
            e.extra = extra; e.runsRan = ran; e.runsOffBat = bat
            append(e); showExtras = false
        }
    }
    private var wicketSheet: some View {
        WicketSheet(battingPlayers: battingPlayers, bowlingPlayers: bowlingPlayers,
                    strikerID: state.strikerID, nonStrikerID: state.nonStrikerID,
                    name: name) { configured in
            var e = pendingEvent ?? baseEvent()
            e.isWicket = true; e.dismissal = configured.dismissal
            e.outBatterID = configured.outBatterID; e.fielderID = configured.fielderID
            e.secondFielderID = configured.secondFielderID
            e.runsRan = configured.runsRan; e.runsOffBat = configured.runsOffBat
            e.extra = configured.extra; e.crossed = configured.crossed
            append(e); showWicket = false
        }
    }
    private var bowlerSheet: some View {
        BowlerPickerSheet(players: bowlingPlayers, state: state,
                          previousBowlerID: state.previousBowlerID,
                          maxOvers: ScoringEngine.maxOversPerBowler(oversPerInnings: match.oversPerInnings),
                          name: name) { bowler in
            setBowler(bowler); showBowlerPicker = false
        }
    }
    private var openersSheet: some View {
        OpenersSheet(battingPlayers: battingPlayers, bowlingPlayers: bowlingPlayers, name: name) { striker, nonStriker, bowler in
            guard let inn = innings else { return }
            var e = BallEventData()
            e.sequence = 0; e.strikerID = striker.id; e.nonStrikerID = nonStriker.id; e.bowlerID = bowler.id
            e.runsOffBat = 0
            // Opener marker: a 0-run legal placeholder is wrong, so store selections
            // on a swap-marker-style setup event with no runs and not legal.
            e.isSwapMarker = true; e.note = "OPENERS"
            var list = inn.events; list.append(e); resequence(&list); inn.events = list
            match.status = .live; try? context.save()
            showOpeners = false
        }
    }
    private func ballEditorSheet(_ ev: BallEventData) -> some View {
        BallEditorSheet(event: ev, battingPlayers: battingPlayers,
                        bowlingPlayers: bowlingPlayers, name: name) { updated in
            saveEdited(updated); editingEvent = nil
        } onDelete: {
            deleteEvent(ev); editingEvent = nil
        }
    }

    // MARK: - Actions

    private func baseEvent() -> BallEventData {
        var e = BallEventData()
        e.strikerID = state.strikerID; e.nonStrikerID = state.nonStrikerID
        e.bowlerID = state.currentBowlerID
        return e
    }
    private func append(_ e: BallEventData) {
        guard let inn = innings else { return }
        var ev = e
        if ev.bowlerID == nil { ev.bowlerID = state.currentBowlerID }
        if ev.strikerID == nil { ev.strikerID = state.strikerID }
        if ev.nonStrikerID == nil { ev.nonStrikerID = state.nonStrikerID }
        var list = inn.events; ev.sequence = (list.map(\.sequence).max() ?? -1) + 1
        list.append(ev); inn.events = list
        match.status = .live; try? context.save()
        // Over just completed with balls remaining in the match: prompt for bowler.
        let newState = ScoringEngine.replay(events: list, playersPerSide: match.playersPerSide,
            oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: names)
        if newState.legalBalls % match.ballsPerOver == 0, newState.legalBalls > 0, !newState.isComplete {
            showBowlerPicker = true
        }
    }
    private func recordRuns(_ runs: Int) {
        var e = baseEvent(); e.runsOffBat = runs; append(e)
    }
    private func undoLast() {
        guard let inn = innings, !inn.events.isEmpty else { return }
        var list = inn.events
        // Copy the target ID out first: reading `list` inside its own
        // mutating removeAll closure violates exclusive access.
        let lastID = list.max(by: { $0.sequence < $1.sequence })?.id
        list.removeAll { $0.id == lastID }
        inn.events = list; try? context.save()
    }
    private func addSwapMarker() {
        guard let inn = innings else { return }
        var e = BallEventData(); e.isSwapMarker = true
        e.strikerID = state.strikerID; e.nonStrikerID = state.nonStrikerID; e.bowlerID = state.currentBowlerID
        var list = inn.events; e.sequence = (list.map(\.sequence).max() ?? -1) + 1
        list.append(e); inn.events = list; try? context.save()
    }
    private func bringInBatter(_ player: Player) {
        // Recorded implicitly: the next ball carries the new batter at the empty
        // end. We persist it as a swap-marker carrying the selection so Undo works.
        guard let inn = innings else { return }
        var e = BallEventData(); e.isSwapMarker = true; e.note = "NEW_BATTER"
        if state.strikerID == nil { e.strikerID = player.id; e.nonStrikerID = state.nonStrikerID }
        else { e.nonStrikerID = player.id; e.strikerID = state.strikerID }
        e.bowlerID = state.currentBowlerID
        var list = inn.events; e.sequence = (list.map(\.sequence).max() ?? -1) + 1
        list.append(e); inn.events = list; try? context.save()
    }
    private func setBowler(_ player: Player) {
        guard let inn = innings else { return }
        // Attach to a marker so the choice itself is undoable and survives reload.
        var e = BallEventData(); e.isSwapMarker = true; e.note = "BOWLER"
        e.strikerID = state.strikerID; e.nonStrikerID = state.nonStrikerID; e.bowlerID = player.id
        var list = inn.events; e.sequence = (list.map(\.sequence).max() ?? -1) + 1
        list.append(e); inn.events = list; try? context.save()
    }
    private func saveEdited(_ updated: BallEventData) {
        guard let inn = innings else { return }
        var list = inn.events
        if let i = list.firstIndex(where: { $0.id == updated.id }) { list[i] = updated }
        inn.events = list; try? context.save()
    }
    private func deleteEvent(_ ev: BallEventData) {
        guard let inn = innings else { return }
        var list = inn.events; list.removeAll { $0.id == ev.id }
        resequence(&list); inn.events = list; try? context.save()
    }
    private func resequence(_ list: inout [BallEventData]) {
        list.sort { $0.sequence < $1.sequence }
        for i in list.indices { list[i].sequence = i }
    }
    private func endInnings() {
        guard let inn = innings else { return }
        inn.isCompleted = true
        match.status = canStartNextInnings ? .inningsBreak : .completed
        try? context.save()
    }
    private func startNextInnings() {
        let nextNumber = (innings?.inningsNumber ?? 0) + 1
        let first = match.battingFirst
        // Innings order: 1: first, 2: other, 3: first (2nd inn), 4: other.
        let batting: TeamSide = nextNumber % 2 == 1 ? first : first.other
        let inn = Innings(inningsNumber: nextNumber, battingSide: batting)
        inn.match = match; match.inningsList.append(inn); context.insert(inn)
        match.status = .live; try? context.save()
        selectedInningsID = inn.id
        showOpeners = true
    }
}

struct ScorePadButtonStyle: ButtonStyle {
    var tint: Color = CricketTheme.pitchGreen
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(tint.opacity(configuration.isPressed ? 0.35 : 0.16), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sub-sheets

struct ExtrasSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ExtraKind = .wide
    @State private var ran = 0
    @State private var bat = 0
    let onApply: (ExtraKind, Int, Int) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Picker("Extra", selection: $kind) {
                    ForEach([ExtraKind.wide, .noBall, .bye, .legBye, .noBallBye, .noBallLegBye], id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                Stepper("Runs ran / byes: \(ran)", value: $ran, in: 0...12)
                if kind == .noBall {
                    Stepper("Runs off bat (no-ball only): \(bat)", value: $bat, in: 0...12)
                }
                Text(helpText).font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Extras")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(kind, ran, kind == .noBall ? bat : 0) }
                }
            }
        }
    }
    private var helpText: String {
        switch kind {
        case .wide: return "1 run penalty added automatically, plus any runs ran. Not a legal ball."
        case .noBall: return "1 run penalty added automatically. Not a legal ball. Bat runs go to the striker."
        case .bye, .legBye: return "Legal ball. Runs go to extras, not the batter or bowler."
        default: return "1 run penalty plus byes/leg-byes ran. Not a legal ball."
        }
    }
}

struct WicketConfig {
    var dismissal: DismissalKind = .bowled
    var outBatterID: UUID? = nil
    var fielderID: UUID? = nil
    var secondFielderID: UUID? = nil
    var runsRan = 0, runsOffBat = 0
    var extra: ExtraKind = .none
    var crossed = false
}
struct WicketSheet: View {
    @Environment(\.dismiss) private var dismiss
    let battingPlayers: [Player], bowlingPlayers: [Player]
    let strikerID: UUID?, nonStrikerID: UUID?
    let name: (UUID?) -> String
    let onApply: (WicketConfig) -> Void
    @State private var cfg = WicketConfig()
    var body: some View {
        NavigationStack {
            Form {
                Picker("Dismissal", selection: $cfg.dismissal) {
                    ForEach(DismissalKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Batter out", selection: $cfg.outBatterID) {
                    Text("Striker — \(name(strikerID))").tag(strikerID)
                    Text("Non-striker — \(name(nonStrikerID))").tag(nonStrikerID)
                }
                if [.caught, .runOut, .stumped].contains(cfg.dismissal) {
                    Picker("Fielder", selection: $cfg.fielderID) {
                        Text("Skip / unknown").tag(UUID?.none)
                        ForEach(bowlingPlayers) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Stepper("Runs completed: \(cfg.runsRan)", value: $cfg.runsRan, in: 0...12)
                Toggle("Batters crossed", isOn: $cfg.crossed)
                Text("After applying, pick the next batter on the scorer screen. Retired Hurt does not count as a wicket and the batter may return later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Wicket")
            .onAppear { if cfg.outBatterID == nil { cfg.outBatterID = strikerID } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Wicket") { onApply(cfg); dismiss() }
                }
            }
        }
    }
}

struct BowlerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let players: [Player], state: InningsState, previousBowlerID: UUID?, maxOvers: Int
    let name: (UUID?) -> String
    let onPick: (Player) -> Void
    var body: some View {
        NavigationStack {
            List(players) { p in
                let f = state.bowlerFigures[p.id]
                let done = (f?.legalBalls ?? 0) >= maxOvers * 6
                Button {
                    onPick(p); dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name.isEmpty ? "Player \(p.battingOrder + 1)" : p.name)
                            Text("\(f?.oversText ?? "0.0") overs • \(f?.wickets ?? 0)/\(f?.runs ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.id == previousBowlerID { Text("Last over").font(.caption2).foregroundStyle(.orange) }
                        if done { Text("Max overs").font(.caption2).foregroundStyle(.red) }
                    }
                }.disabled(done)
            }
            .navigationTitle("Select Bowler")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct OpenersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let battingPlayers: [Player], bowlingPlayers: [Player]
    let name: (UUID?) -> String
    let onStart: (Player, Player, Player) -> Void
    @State private var striker: Player?
    @State private var nonStriker: Player?
    @State private var bowler: Player?
    var body: some View {
        NavigationStack {
            Form {
                Section("Striker") { playerPicker(selection: $striker, players: battingPlayers) }
                Section("Non-striker") { playerPicker(selection: $nonStriker, players: battingPlayers) }
                Section("Opening bowler") { playerPicker(selection: $bowler, players: bowlingPlayers) }
            }
            .navigationTitle("Innings Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Innings") {
                        if let s = striker, let n = nonStriker, let b = bowler, s.id != n.id {
                            onStart(s, n, b); dismiss()
                        }
                    }.disabled(striker == nil || nonStriker == nil || bowler == nil || striker?.id == nonStriker?.id)
                }
            }
        }
    }
    private func playerPicker(selection: Binding<Player?>, players: [Player]) -> some View {
        Picker("Player", selection: Binding(
            get: { selection.wrappedValue?.id },
            set: { id in selection.wrappedValue = players.first { $0.id == id } })) {
            Text("— Select —").tag(UUID?.none)
            ForEach(players) { Text($0.name.isEmpty ? "Player \($0.battingOrder + 1)" : $0.name).tag(UUID?.some($0.id)) }
        }
    }
}

struct BallEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var event: BallEventData
    let battingPlayers: [Player], bowlingPlayers: [Player]
    let name: (UUID?) -> String
    let onSave: (BallEventData) -> Void
    let onDelete: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Delivery") {
                    Stepper("Runs off bat: \(event.runsOffBat)", value: $event.runsOffBat, in: 0...12)
                    Picker("Extra", selection: $event.extra) {
                        ForEach(ExtraKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Stepper("Runs ran (extras): \(event.runsRan)", value: $event.runsRan, in: 0...12)
                    Toggle("Wicket", isOn: $event.isWicket)
                    if event.isWicket {
                        Picker("Dismissal", selection: Binding(
                            get: { event.dismissal ?? .bowled },
                            set: { event.dismissal = $0 })) {
                            ForEach(DismissalKind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    TextField("Note", text: $event.note)
                }
                Section {
                    Picker("Striker", selection: $event.strikerID) {
                        Text("—").tag(UUID?.none)
                        ForEach(battingPlayers) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Bowler", selection: $event.bowlerID) {
                        Text("—").tag(UUID?.none)
                        ForEach(bowlingPlayers) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section {
                    Button("Delete This Ball", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle("Fix Ball")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Fix") { onSave(event); dismiss() }
                }
            }
        }
    }
}
