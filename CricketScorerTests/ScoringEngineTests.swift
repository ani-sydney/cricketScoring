import XCTest

/// Regression suite for the replay engine. The ball log is the source of
/// truth, so these tests replay raw `BallEventData` and assert derived
/// figures — including the end-of-over path that previously held the bad
/// closure in LiveScoringView (building this target also builds those files).
final class ScoringEngineTests: XCTestCase {

    private var players: [UUID] = []
    private var names: [UUID: String] = [:]

    override func setUp() {
        super.setUp()
        players = (0..<11).map { _ in UUID() }
        names = Dictionary(uniqueKeysWithValues: players.enumerated().map {
            ($0.element, "P\($0.offset)")
        })
    }

    private func ball(seq: Int, bat: Int = 0, extra: ExtraKind = ExtraKind.none,
                      ran: Int = 0, wicket: Bool = false,
                      dismissal: DismissalKind? = nil) -> BallEventData {
        var e = BallEventData()
        e.sequence = seq
        e.strikerID = players[0]
        e.nonStrikerID = players[1]
        e.bowlerID = players[10]
        e.runsOffBat = bat
        e.extra = extra
        e.runsRan = ran
        e.isWicket = wicket
        e.dismissal = dismissal
        e.outBatterID = wicket ? players[0] : nil
        return e
    }

    private func replay(_ events: [BallEventData], overs: Int = 20) -> InningsState {
        ScoringEngine.replay(events: events, playersPerSide: 11,
                             oversPerInnings: overs, ballsPerOver: 6, names: names)
    }

    func testRunsAndBoundariesTotalCorrectly() {
        let state = replay([
            ball(seq: 0, bat: 4), ball(seq: 1, bat: 1),
            ball(seq: 2, bat: 6), ball(seq: 3, bat: 2),
        ])
        XCTAssertEqual(state.totalRuns, 13)
        XCTAssertEqual(state.wickets, 0)
        XCTAssertEqual(state.legalBalls, 4)
    }

    func testWideIsNotALegalBallAndAddsPenaltyRun() {
        let state = replay([ball(seq: 0, extra: ExtraKind.wide)])
        XCTAssertEqual(state.totalRuns, 1)
        XCTAssertEqual(state.legalBalls, 0)
    }

    func testNoBallAddsPenaltyAndBatRunsButNotLegalBall() {
        let state = replay([ball(seq: 0, bat: 2, extra: ExtraKind.noBall)])
        XCTAssertEqual(state.totalRuns, 3)
        XCTAssertEqual(state.legalBalls, 0)
    }

    func testByeCountsAsLegalBallButNotBatterRuns() {
        let state = replay([ball(seq: 0, extra: ExtraKind.bye, ran: 2)])
        XCTAssertEqual(state.totalRuns, 2)
        XCTAssertEqual(state.legalBalls, 1)
        XCTAssertEqual(state.batterFigures[players[0]]?.runs, 0)
    }

    func testWicketIncrementsAndClearsStrikerEnd() {
        let state = replay([
            ball(seq: 0, bat: 0),
            ball(seq: 1, wicket: true, dismissal: DismissalKind.bowled),
        ])
        XCTAssertEqual(state.wickets, 1)
        XCTAssertNil(state.strikerID)
        XCTAssertEqual(state.fallOfWickets.count, 1)
    }

    /// Undo = dropping the last event. Replay must recompute cleanly with
    /// no stale totals left behind.
    func testUndoByDroppingLastEventRecomputes() {
        let events = [
            ball(seq: 0, bat: 4), ball(seq: 1, bat: 1),
            ball(seq: 2, extra: ExtraKind.wide), ball(seq: 3, bat: 6),
            ball(seq: 4, wicket: true, dismissal: DismissalKind.bowled),
            ball(seq: 5, bat: 2),
        ]
        XCTAssertEqual(replay(events).totalRuns, 14)
        let undone = replay(Array(events.dropLast()))
        XCTAssertEqual(undone.totalRuns, 12)
        XCTAssertEqual(undone.wickets, 1)
        XCTAssertEqual(undone.legalBalls, 4)
    }

    func testOverCompletesAfterSixLegalBalls() {
        let events = (0..<6).map { ball(seq: $0, bat: 1) }
        let state = replay(events)
        XCTAssertEqual(state.legalBalls, 6)
        XCTAssertEqual(state.oversText, "1.0")
        XCTAssertFalse(state.isComplete)
    }

    func testInningsEndsWhenOversExhausted() {
        let events = (0..<12).map { ball(seq: $0, bat: 0) }
        let state = replay(events, overs: 2)
        XCTAssertTrue(state.oversExhausted)
        XCTAssertTrue(state.isComplete)
    }

    func testAllOutAfterTenWickets() {
        var events: [BallEventData] = []
        for i in 0..<10 {
            var e = ball(seq: i, wicket: true, dismissal: DismissalKind.bowled)
            e.outBatterID = players[i % 11]
            e.strikerID = players[i % 11]
            events.append(e)
        }
        let state = replay(events)
        XCTAssertEqual(state.wickets, 10)
        XCTAssertTrue(state.isAllOut)
        XCTAssertTrue(state.isComplete)
    }

    func testRetiredHurtDoesNotCountAsWicket() {
        let state = replay([
            ball(seq: 0, wicket: true, dismissal: DismissalKind.retiredHurt),
        ])
        XCTAssertEqual(state.wickets, 0)
    }

    // MARK: - Duplicate player names (blocking policy)

    func testNormalizedNameIgnoresCaseAndSpacing() {
        XCTAssertEqual(normalizedPlayerName("  Sam   Patel "), "sam patel")
        XCTAssertEqual(normalizedPlayerName("SAM PATEL"), "sam patel")
    }

    func testDuplicateDetectionIgnoresCaseAndSpacing() {
        XCTAssertTrue(isDuplicatePlayerName(" sam  patel ", among: ["Sam Patel", "Jo Lee"]))
        XCTAssertFalse(isDuplicatePlayerName("Sam Patil", among: ["Sam Patel"]))
    }

    func testEmptyNamesAreNeverDuplicates() {
        XCTAssertFalse(isDuplicatePlayerName("", among: ["", ""]))
        XCTAssertFalse(isDuplicatePlayerName("   ", among: ["Sam Patel"]))
    }

    func testBowlerFiguresChargeWidesButNotByes() {
        let state = replay([
            ball(seq: 0, extra: ExtraKind.wide),
            ball(seq: 1, extra: ExtraKind.bye, ran: 2),
            ball(seq: 2, bat: 3),
        ])
        let bowler = state.bowlerFigures[players[10]]
        XCTAssertEqual(bowler?.legalBalls, 2)
        XCTAssertEqual(bowler?.runs, 4) // 1 wide penalty + 3 off bat; byes excluded
        XCTAssertEqual(bowler?.wides, 1)
    }
}
