import XCTest

/// Start-to-end demo driver: splash → create match → squads → toss →
/// scoring (runs, extras, wicket) → fixes (undo, swap, next batter) →
/// scorecard popup → end innings → next innings → SCA PDF export/share.
/// Run via Scripts/record-demo.sh, which records the Simulator screen
/// while this test taps through the real app. Steps are best-effort
/// (tapIfExists) so the recording always runs to the end card.
final class DemoFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-demoMode"]
        app.launch()
    }

    // MARK: - Helpers

    private func pause(_ seconds: TimeInterval = 1.6) {
        Thread.sleep(forTimeInterval: seconds)
    }
    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }
    private func tapButton(_ label: String, timeout: TimeInterval = 4) {
        tapIfExists(app.buttons[label].firstMatch, timeout: timeout)
    }
    private func tapText(_ label: String, timeout: TimeInterval = 4) {
        if tapIfExists(app.buttons[label].firstMatch, timeout: timeout) { return }
        tapIfExists(app.staticTexts[label].firstMatch, timeout: timeout)
    }
    private func typeInto(_ field: XCUIElement, _ text: String) {
        guard field.waitForExistence(timeout: 4) else { return }
        field.tap()
        field.typeText(text)
    }
    /// SwiftUI Form pickers present as tappable rows, then a menu of options.
    private func choosePickerOption(containing rowText: String, option: String) {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", rowText)).firstMatch
        if !tapIfExists(row, timeout: 3) {
            tapIfExists(app.staticTexts[rowText].firstMatch, timeout: 2)
        }
        pause(0.7)
        if tapIfExists(app.buttons[option].firstMatch, timeout: 3) { return }
        tapIfExists(app.staticTexts[option].firstMatch, timeout: 2)
    }

    // MARK: - Start-to-end demo

    func testDemoWalkthrough() {
        // 1. Splash + home
        pause(3.2)

        // 2. Create match (teams + format + toss defaults: Team A wins, bats)
        tapButton("New Match")
        pause()
        let teamA = app.textFields["Team A name"].firstMatch
        typeInto(teamA, "Harbour CC")
        let teamB = app.textFields["Team B name"].firstMatch
        typeInto(teamB, "City CC")
        pause()
        tapButton("Create")
        pause()

        // 3. Open the match
        tapText("Harbour CC v City CC")
        pause()

        // 4. Squads: name the openers and a bowler (rename flow)
        tapText("Harbour CC")
        pause()
        renamePlayer(at: 0, to: "J Smith")
        renamePlayer(at: 1, to: "R Lee")
        goBack()
        tapText("City CC")
        pause()
        renamePlayer(at: 0, to: "T Brown")
        renamePlayer(at: 1, to: "A Khan")
        goBack()
        pause()

        // 5. Start scoring: openers + opening bowler
        tapText("Start Scoring")
        pause()
        choosePickerOption(containing: "Player", option: "J Smith")
        choosePickerOption(containing: "Player", option: "R Lee")
        choosePickerOption(containing: "Player", option: "T Brown")
        tapButton("Start Innings")
        pause()

        // 6. Ball-by-ball: 4, 1, Wide (Extras), 6
        tapButton("4"); pause(0.9)
        tapButton("1"); pause(0.9)
        tapButton("Extras"); pause()
        tapButton("Apply"); pause(0.9)
        tapButton("6"); pause(0.9)

        // 7. Wicket, then next batter comes in
        tapButton("Wicket"); pause()
        tapButton("Apply Wicket"); pause()
        tapText("T Brown") // fielder-named candidate if present; harmless if absent
        // Next-batter list: tap the first available batter row
        if app.buttons.count > 2 { /* candidates appear as bordered buttons */ }
        pause()

        // 8. Fixes: swap striker, score, undo
        tapButton("Swap Striker"); pause(0.9)
        tapButton("2"); pause(0.9)
        tapButton("Undo"); pause()

        // 9. Quick scorecard popup, then dismiss
        tapIfExists(app.buttons["Show scorecard"].firstMatch)
        pause(2.2)
        tapButton("Done")
        pause()

        // 10. End innings, start the next one, score a ball
        openMenuItem("End Innings")
        tapButton("End Innings") // alert confirmation
        pause()
        openMenuItem("Start Next Innings")
        pause()
        choosePickerOption(containing: "Player", option: "T Brown")
        choosePickerOption(containing: "Player", option: "A Khan")
        choosePickerOption(containing: "Player", option: "J Smith")
        tapButton("Start Innings")
        pause()
        tapButton("1"); pause()

        // 11. Scorecard + SCA Score Book PDF export via iOS share sheet
        goBack()
        tapText("Scorecard & Ball-by-Ball")
        pause()
        tapButton("Share Scorebook PDF")
        pause(2.6) // share sheet on screen: Messages / Mail / AirDrop / Files
        tapIfExists(app.buttons["Close"].firstMatch, timeout: 2)
        pause()

        // 12. End card hold
        goBack()
        pause(2.0)
    }

    private func renamePlayer(at index: Int, to name: String) {
        let fields = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Player name'"))
        let field = fields.element(boundBy: index)
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap()
        field.typeText(name + "\n")
        pause(0.6)
    }
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        tapIfExists(back, timeout: 3)
        pause(0.8)
    }
    private func openMenuItem(_ label: String) {
        // Top-bar ellipsis menu on Live Scoring
        let menu = app.buttons["More"].firstMatch.exists
            ? app.buttons["More"].firstMatch
            : app.navigationBars.buttons.element(boundBy: 1)
        tapIfExists(menu, timeout: 3)
        pause(0.7)
        tapText(label)
    }
}
