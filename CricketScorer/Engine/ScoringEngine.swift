import Foundation

struct BatterFigure: Identifiable, Equatable {
    var id: UUID
    var runs = 0, balls = 0, fours = 0, sixes = 0
    var isOut = false, hasBatted = false
    var dismissalText = "not out"
    var strikeRate: Double { balls > 0 ? Double(runs) / Double(balls) * 100 : 0 }
}
struct BowlerFigure: Identifiable, Equatable {
    var id: UUID
    var legalBalls = 0, runs = 0, wickets = 0, wides = 0, noBalls = 0
    var oversText: String { "\(legalBalls / 6).\(legalBalls % 6)" }
    var economy: Double { legalBalls > 0 ? Double(runs) / (Double(legalBalls) / 6) : 0 }
}
struct InningsState: Equatable {
    var totalRuns = 0, wickets = 0, legalBalls = 0
    var strikerID: UUID? = nil, nonStrikerID: UUID? = nil
    var currentBowlerID: UUID? = nil, previousBowlerID: UUID? = nil
    var batterFigures: [UUID: BatterFigure] = [:]
    var bowlerFigures: [UUID: BowlerFigure] = [:]
    var fallOfWickets: [(score: Int, over: String, batterID: UUID?)] = []
    var extrasBreakdown: [String: Int] = [:]
    var isAllOut = false, oversExhausted = false
    var oversText: String { "\(legalBalls / 6).\(legalBalls % 6)" }
    var isComplete: Bool { isAllOut || oversExhausted }
    static func == (lhs: InningsState, rhs: InningsState) -> Bool {
        lhs.totalRuns == rhs.totalRuns && lhs.wickets == rhs.wickets
            && lhs.legalBalls == rhs.legalBalls && lhs.strikerID == rhs.strikerID
            && lhs.nonStrikerID == rhs.nonStrikerID && lhs.isComplete == rhs.isComplete
    }
}

/// Pure replay engine: folds the ordered ball log into score, strike, and
/// batting/bowling figures. No SwiftData / UI dependency, so it is unit-testable.
enum ScoringEngine {
    static func replay(events: [BallEventData], playersPerSide: Int,
                       oversPerInnings: Int, ballsPerOver: Int,
                       names: [UUID: String]) -> InningsState {
        var s = InningsState()
        let maxLegal = oversPerInnings * ballsPerOver
        let maxWickets = max(1, playersPerSide - 1)
        for e in events.sorted(by: { $0.sequence < $1.sequence }) {
            if e.isSwapMarker {
                // Setup markers carry explicit selections; a plain marker swaps ends.
                if e.note == "OPENERS" || e.note == "NEW_BATTER" || e.note == "BOWLER" {
                    if let v = e.strikerID { s.strikerID = v }
                    if let v = e.nonStrikerID { s.nonStrikerID = v }
                    if let v = e.bowlerID { s.currentBowlerID = v }
                } else if s.strikerID != nil {
                    swap(&s.strikerID, &s.nonStrikerID)
                }
                continue
            }
            if s.strikerID == nil { s.strikerID = e.strikerID }
            if s.nonStrikerID == nil { s.nonStrikerID = e.nonStrikerID }
            if let b = e.bowlerID { s.currentBowlerID = b }
            s.totalRuns += e.teamRuns
            if e.extraRunsTotal > 0 {
                s.extrasBreakdown[e.extra.label, default: 0] += e.extraRunsTotal
            }
            // Batter figure (wides don't count as a ball faced).
            if let st = s.strikerID {
                var f = s.batterFigures[st] ?? BatterFigure(id: st)
                f.hasBatted = true
                f.runs += e.batterRuns
                if e.extra != .wide { f.balls += 1 }
                if e.isFour { f.fours += 1 }
                if e.isSix { f.sixes += 1 }
                s.batterFigures[st] = f
            }
            // Bowler figure (byes/leg-byes don't count against the bowler).
            if let bw = e.bowlerID {
                var f = s.bowlerFigures[bw] ?? BowlerFigure(id: bw)
                if e.isLegal { f.legalBalls += 1 }
                f.runs += e.batterRuns + (e.extra == .wide || e.extra == .noBall
                    || e.extra == .noBallBye || e.extra == .noBallLegBye ? e.extraRunsTotal : 0)
                if e.extra == .wide { f.wides += 1 }
                if e.extra == .noBall || e.extra == .noBallBye || e.extra == .noBallLegBye { f.noBalls += 1 }
                if e.isWicket, let d = e.dismissal, d != .runOut, d.countsAsWicket { f.wickets += 1 }
                s.bowlerFigures[bw] = f
            }
            if e.isLegal { s.legalBalls += 1 }
            // Strike rotation: odd completed runs swap ends.
            let completed = e.batterRuns + (e.extra == .none || e.extra == .noBall ? 0 : e.runsRan)
                + ((e.dismissal == .runOut) ? 0 : 0)
            let runningRuns = e.isWicket && e.dismissal == .runOut
                ? e.runsRan : completed
            if runningRuns % 2 == 1 { swap(&s.strikerID, &s.nonStrikerID) }
            // Dismissal: mark out, record fall of wicket, clear the end.
            if e.isWicket, let outID = e.outBatterID ?? s.strikerID {
                if e.dismissal?.countsAsWicket == true { s.wickets += 1 }
                var f = s.batterFigures[outID] ?? BatterFigure(id: outID)
                f.hasBatted = true
                if e.dismissal != .retiredHurt {
                    f.isOut = true
                    f.dismissalText = dismissalText(e, names: names)
                } else { f.dismissalText = "retired hurt" }
                s.batterFigures[outID] = f
                if e.dismissal?.countsAsWicket == true {
                    s.fallOfWickets.append((s.totalRuns,
                        "\(s.legalBalls / ballsPerOver).\(s.legalBalls % ballsPerOver)", outID))
                }
                if s.strikerID == outID { s.strikerID = nil }
                if s.nonStrikerID == outID { s.nonStrikerID = nil }
                if e.crossed && s.strikerID == nil && s.nonStrikerID != nil {
                    // Batters crossed on a caught dismissal: survivor takes strike.
                }
            }
            if s.wickets >= maxWickets { s.isAllOut = true }
            if s.legalBalls >= maxLegal { s.oversExhausted = true }
            // End of over: swap ends, remember bowler (can't bowl consecutive overs).
            if e.isLegal, ballsPerOver > 0, s.legalBalls % ballsPerOver == 0, s.legalBalls > 0 {
                s.previousBowlerID = s.currentBowlerID
                swap(&s.strikerID, &s.nonStrikerID)
            }
        }
        return s
    }

    static func dismissalText(_ e: BallEventData, names: [UUID: String]) -> String {
        func n(_ id: UUID?) -> String { id.flatMap { names[$0] } ?? "?" }
        switch e.dismissal {
        case .bowled: return "b \(n(e.bowlerID))"
        case .caught: return "c \(n(e.fielderID)) b \(n(e.bowlerID))"
        case .caughtAndBowled: return "c & b \(n(e.bowlerID))"
        case .lbw: return "lbw b \(n(e.bowlerID))"
        case .runOut: return "run out (\(n(e.fielderID)))"
        case .stumped: return "st \(n(e.fielderID)) b \(n(e.bowlerID))"
        case .hitWicket: return "hit wicket b \(n(e.bowlerID))"
        case .retiredHurt: return "retired hurt"
        case .retiredOut: return "retired out"
        case .timedOut: return "timed out"
        case .obstructingField: return "obstructing field"
        case .hitBallTwice: return "hit ball twice"
        case .handledBall: return "handled ball"
        case nil: return "out"
        }
    }

    /// Batters still available to come in (not out, not currently batting).
    static func nextBatterCandidates(innings: Innings, state: InningsState,
                                     battingPlayers: [Player]) -> [Player] {
        battingPlayers.filter { p in
            let f = state.batterFigures[p.id]
            return f?.isOut != true && p.id != state.strikerID && p.id != state.nonStrikerID
        }
    }
    /// Max overs a bowler may bowl in a limited-overs innings.
    static func maxOversPerBowler(oversPerInnings: Int) -> Int {
        max(1, Int(ceil(Double(oversPerInnings) / 5.0)))
    }
}
