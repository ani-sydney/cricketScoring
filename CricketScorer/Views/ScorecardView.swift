import SwiftUI
import SwiftData

struct ScorecardView: View {
    @Bindable var match: Match
    private var names: [UUID: String] { Dictionary(uniqueKeysWithValues: match.players.map { ($0.id, $0.name.isEmpty ? "Player \($0.battingOrder + 1)" : $0.name) }) }

    var body: some View {
        List {
            ForEach(match.inningsList.sorted { $0.inningsNumber < $1.inningsNumber }) { inn in
                inningsSection(inn)
            }
            Section {
                ShareLink(item: exportText) {
                    Label("Share Scorecard", systemImage: "square.and.arrow.up")
                }
                Text("Stored only on this device (SwiftData). Share sends a text scorecard wherever you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scorecard")
    }

    @ViewBuilder private func inningsSection(_ inn: Innings) -> some View {
        let state = ScoringEngine.replay(events: inn.events, playersPerSide: match.playersPerSide,
            oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: names)
        let batting = match.players(for: inn.battingSide)
        let bowling = match.players(for: inn.battingSide.other)
        Section {
            LabeledContent("Total", value: "\(state.totalRuns)/\(state.wickets) (\(state.oversText) ov)")
            if !state.extrasBreakdown.isEmpty {
                LabeledContent("Extras", value: state.extrasBreakdown
                    .map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", "))
            }
        } header: {
            Text("Innings \(inn.inningsNumber) — \(match.teamName(inn.battingSide))\(inn.isCompleted ? " (closed)" : "")")
        }
        Section("Batting — \(match.teamName(inn.battingSide))") {
            ForEach(batting) { p in
                let f = state.batterFigures[p.id]
                HStack {
                    VStack(alignment: .leading) {
                        Text(p.name.isEmpty ? "Player \(p.battingOrder + 1)" : p.name)
                        Text(f?.hasBatted == true ? (f?.dismissalText ?? "") : "did not bat")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let f, f.hasBatted {
                        Text("\(f.runs) (\(f.balls))").monospacedDigit()
                    }
                }
            }
        }
        Section("Bowling — \(match.teamName(inn.battingSide.other))") {
            ForEach(bowling) { p in
                if let f = state.bowlerFigures[p.id] {
                    HStack {
                        Text(p.name.isEmpty ? "Player \(p.battingOrder + 1)" : p.name)
                        Spacer()
                        Text("\(f.oversText)-\(f.wickets)/\(f.runs)").monospacedDigit()
                    }
                }
            }
        }
        if !state.fallOfWickets.isEmpty {
            Section("Fall of Wickets") {
                ForEach(Array(state.fallOfWickets.enumerated()), id: \.offset) { pair in
                    Text("\(pair.offset + 1)-\(pair.element.score) (\(pair.element.over) ov) \(pair.element.batterID.flatMap { names[$0] } ?? "")")
                        .font(.caption)
                }
            }
        }
        Section("Ball-by-Ball") {
            ForEach(inn.events.sorted { $0.sequence < $1.sequence }) { e in
                if !e.isSwapMarker {
                    HStack {
                        Text(e.symbol).bold().frame(width: 46, alignment: .leading)
                        Text("\(e.strikerID.flatMap { names[$0] } ?? "—") • \(e.extra == .none ? "" : e.extra.label + " ")\(e.isWicket ? (e.dismissal?.label ?? "Wicket") : "\(e.runsOffBat)")")
                            .font(.caption)
                    }
                }
            }
        }
    }

    var exportText: String {
        var lines = ["\(match.teamAName) v \(match.teamBName)",
                     "Toss: \(match.teamName(match.tossWinner)) won, elected to \(match.tossDecision.rawValue)",
                     "Format: \(match.oversPerInnings) overs, \(match.playersPerSide)-a-side", ""]
        for inn in match.inningsList.sorted(by: { $0.inningsNumber < $1.inningsNumber }) {
            let state = ScoringEngine.replay(events: inn.events, playersPerSide: match.playersPerSide,
                oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: names)
            lines.append("Innings \(inn.inningsNumber): \(match.teamName(inn.battingSide)) \(state.totalRuns)/\(state.wickets) (\(state.oversText) ov)")
            for p in match.players(for: inn.battingSide) {
                if let f = state.batterFigures[p.id], f.hasBatted {
                    lines.append("  \(p.name) \(f.dismissalText) \(f.runs) (\(f.balls))")
                }
            }
            for p in match.players(for: inn.battingSide.other) {
                if let f = state.bowlerFigures[p.id] {
                    lines.append("  Bowling: \(p.name) \(f.oversText)-\(f.wickets)/\(f.runs)")
                }
            }
            lines.append("")
        }
        lines.append(resultText)
        return lines.joined(separator: "\n")
    }

    var resultText: String {
        guard match.inningsList.count >= 2,
              let first = match.inningsList.sorted(by: { $0.inningsNumber < $1.inningsNumber }).first,
              let second = match.inningsList.sorted(by: { $0.inningsNumber < $1.inningsNumber }).last,
              second.isCompleted || first.isCompleted else { return "Result: in progress" }
        let n = names
        func total(_ inn: Innings) -> (Int, Int) {
            let s = ScoringEngine.replay(events: inn.events, playersPerSide: match.playersPerSide,
                oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: n)
            return (s.totalRuns, s.wickets)
        }
        let (r1, _) = total(first); let (r2, w2) = total(second)
        if r2 > r1 { return "Result: \(match.teamName(second.battingSide)) won by \(match.playersPerSide - 1 - w2) wickets" }
        if r1 > r2 { return "Result: \(match.teamName(first.battingSide)) won by \(r1 - r2) runs" }
        return "Result: match tied"
    }
}
