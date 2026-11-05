import Foundation
import SwiftData

enum TeamSide: String, Codable, CaseIterable { case a, b
    var other: TeamSide { self == .a ? .b : .a } }
enum TossDecision: String, Codable, CaseIterable { case bat, bowl }
enum MatchStatus: String, Codable { case setup, live, inningsBreak, completed }
enum ExtraKind: String, Codable, CaseIterable {
    case none, wide, noBall, bye, legBye, noBallBye, noBallLegBye
    var isLegalBall: Bool { self == .none || self == .bye || self == .legBye }
    var label: String {
        switch self {
        case .none: return "—"
        case .wide: return "Wide"
        case .noBall: return "No Ball"
        case .bye: return "Bye"
        case .legBye: return "Leg Bye"
        case .noBallBye: return "No Ball + Bye"
        case .noBallLegBye: return "No Ball + Leg Bye"
        }
    }
}
enum DismissalKind: String, Codable, CaseIterable {
    case bowled, caught, caughtAndBowled, lbw, runOut, stumped, hitWicket
    case retiredHurt, retiredOut, timedOut, obstructingField, hitBallTwice, handledBall
    var countsAsWicket: Bool { self != .retiredHurt }
    var label: String {
        switch self {
        case .bowled: return "Bowled"
        case .caught: return "Caught"
        case .caughtAndBowled: return "Caught & Bowled"
        case .lbw: return "LBW"
        case .runOut: return "Run Out"
        case .stumped: return "Stumped"
        case .hitWicket: return "Hit Wicket"
        case .retiredHurt: return "Retired Hurt"
        case .retiredOut: return "Retired Out"
        case .timedOut: return "Timed Out"
        case .obstructingField: return "Obstructing Field"
        case .hitBallTwice: return "Hit Ball Twice"
        case .handledBall: return "Handled Ball"
        }
    }
}

/// One recorded delivery (or a manual striker-swap marker). The ordered ball
/// log is the single source of truth — every score is derived by replaying it,
/// which is what makes Undo / Edit Ball / Swap Striker safe.
struct BallEventData: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var sequence: Int = 0
    var isSwapMarker: Bool = false
    var strikerID: UUID?
    var nonStrikerID: UUID?
    var bowlerID: UUID?
    var runsOffBat: Int = 0
    var extra: ExtraKind = .none
    /// Runs completed by running (for wides / byes / no-ball extras).
    var runsRan: Int = 0
    var isWicket: Bool = false
    var dismissal: DismissalKind? = nil
    var outBatterID: UUID? = nil
    var fielderID: UUID? = nil
    var secondFielderID: UUID? = nil
    var crossed: Bool = false
    var note: String = ""

    /// Penalty run for a wide / no-ball, per standard laws.
    var penaltyRuns: Int { (extra == .wide || extra == .noBall || extra == .noBallBye || extra == .noBallLegBye) ? 1 : 0 }
    var extraRunsTotal: Int {
        switch extra {
        case .none: return 0
        case .wide, .noBall: return penaltyRuns + runsRan
        case .bye, .legBye: return runsRan
        case .noBallBye, .noBallLegBye: return penaltyRuns + runsRan
        }
    }
    /// Runs credited to the striker's personal score.
    var batterRuns: Int {
        switch extra {
        case .wide, .bye, .legBye, .noBallBye, .noBallLegBye: return 0
        case .none, .noBall: return runsOffBat
        }
    }
    var teamRuns: Int { batterRuns + extraRunsTotal }
    var isLegal: Bool { extra.isLegalBall && !isSwapMarker }
    var isFour: Bool { batterRuns == 4 }
    var isSix: Bool { batterRuns == 6 }
    var symbol: String {
        if isSwapMarker { return "⇄" }
        if isWicket { return "W" }
        switch extra {
        case .wide: return runsRan > 0 ? "\(1 + runsRan)wd" : "wd"
        case .noBall: return runsOffBat > 0 ? "nb+\(runsOffBat)" : "nb"
        case .noBallBye, .noBallLegBye: return "nb"
        case .bye: return "\(runsRan)b"
        case .legBye: return "\(runsRan)lb"
        case .none: return runsOffBat == 0 ? "•" : "\(runsOffBat)"
        }
    }
}

/// Canonical form for comparing player names: trimmed, single-spaced, lowercased.
/// "  Sam   Patel " and "sam patel" are the same name.
func normalizedPlayerName(_ name: String) -> String {
    name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

/// True when `candidate` already exists in `existingNames` (case/spacing-insensitive).
/// Empty names never count as duplicates (unused squad slots stay empty).
func isDuplicatePlayerName(_ candidate: String, among existingNames: [String]) -> Bool {
    let target = normalizedPlayerName(candidate)
    guard !target.isEmpty else { return false }
    return existingNames.contains { normalizedPlayerName($0) == target }
}

@Model final class Match {
    var id: UUID
    var title: String
    var venue: String
    var matchDate: Date
    var oversPerInnings: Int
    var playersPerSide: Int
    var ballsPerOver: Int
    var inningsPerTeam: Int
    var teamAName: String
    var teamBName: String
    // Stored as raw strings: SwiftData's @Model macro rejects shorthand
    // enum defaults (e.g. `.a`) — "requires a fully qualified domain named value".
    var tossWinnerRaw: String
    var tossDecisionRaw: String
    var statusRaw: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Player.match) var players: [Player]
    @Relationship(deleteRule: .cascade, inverse: \Innings.match) var inningsList: [Innings]
    init() {
        self.id = UUID()
        self.title = ""
        self.venue = ""
        self.matchDate = Date.now
        self.oversPerInnings = 20
        self.playersPerSide = 11
        self.ballsPerOver = 6
        self.inningsPerTeam = 1
        self.teamAName = "Team A"
        self.teamBName = "Team B"
        self.tossWinnerRaw = TeamSide.a.rawValue
        self.tossDecisionRaw = TossDecision.bat.rawValue
        self.statusRaw = MatchStatus.setup.rawValue
        self.createdAt = Date.now
        self.players = []
        self.inningsList = []
    }
    var tossWinner: TeamSide {
        get { TeamSide(rawValue: tossWinnerRaw) ?? TeamSide.a }
        set { tossWinnerRaw = newValue.rawValue }
    }
    var tossDecision: TossDecision {
        get { TossDecision(rawValue: tossDecisionRaw) ?? TossDecision.bat }
        set { tossDecisionRaw = newValue.rawValue }
    }
    var status: MatchStatus {
        get { MatchStatus(rawValue: statusRaw) ?? .setup }
        set { statusRaw = newValue.rawValue }
    }
    /// Blocking rule (chosen policy): a name may be used by only one player
    /// per team. Same name in the opposing team is allowed.
    func isNameTaken(_ name: String, in side: TeamSide, excluding playerID: UUID? = nil) -> Bool {
        let others = players.filter { $0.side == side && $0.id != playerID }.map(\.name)
        return isDuplicatePlayerName(name, among: others)
    }
    func teamName(_ side: TeamSide) -> String { side == .a ? teamAName : teamBName }
    func players(for side: TeamSide) -> [Player] {
        players.filter { $0.side == side }.sorted { $0.battingOrder < $1.battingOrder }
    }
    var battingFirst: TeamSide { tossDecision == .bat ? tossWinner : tossWinner.other }
}

@Model final class Player {
    var id: UUID
    var name: String
    var sideRaw: String
    var battingOrder: Int
    var isWicketKeeper: Bool
    var isCaptain: Bool
    var match: Match?
    init(name: String = "", side: TeamSide = TeamSide.a, battingOrder: Int = 0) {
        self.id = UUID()
        self.name = name; self.sideRaw = side.rawValue; self.battingOrder = battingOrder
        self.isWicketKeeper = false
        self.isCaptain = false
    }
    var side: TeamSide {
        get { TeamSide(rawValue: sideRaw) ?? TeamSide.a }
        set { sideRaw = newValue.rawValue }
    }
}

@Model final class Innings {
    var id: UUID
    var inningsNumber: Int
    var battingSideRaw: String
    var isCompleted: Bool
    var declared: Bool
    /// Ordered ball log, stored as JSON — replayed by `ScoringEngine` for all figures.
    var eventsData: Data
    var match: Match?
    init(inningsNumber: Int = 1, battingSide: TeamSide = TeamSide.a) {
        self.id = UUID()
        self.inningsNumber = inningsNumber; self.battingSideRaw = battingSide.rawValue
        self.isCompleted = false
        self.declared = false
        self.eventsData = Data()
    }
    var battingSide: TeamSide {
        get { TeamSide(rawValue: battingSideRaw) ?? TeamSide.a }
        set { battingSideRaw = newValue.rawValue }
    }
    var events: [BallEventData] {
        get { (try? JSONDecoder().decode([BallEventData].self, from: eventsData)) ?? [] }
        set { eventsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
