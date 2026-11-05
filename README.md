# Cricket Scorer (Local, PlayHQ-style)

Offline iPhone + iPad cricket scorer modelled on the PlayHQ eScoring flow.
Nothing is sent to a server — all matches, players and ball-by-ball events are
stored on-device in **SwiftData**.

## Open & Run

1. Open `CricketScorer.xcodeproj` in Xcode 16+.
2. Select your iPhone or iPad (or a simulator) and press Run.
3. Deployment target iOS 17+, supports iPhone and iPad (`TARGETED_DEVICE_FAMILY 1,2`).

> This workspace has no full Xcode install (Command Line Tools only), so the app
> could not be compiled here. Open it in Xcode for the first build. Set your own
> Team under Signing & Capabilities if you changed the bundle ID.

## Match Day Flow

1. **New Match** — team names, overs (5–50), players per side (5–11), 1 or 2 innings per team.
2. **Toss** — who won and whether they bat or bowl. The batting-first side is derived automatically.
3. **Squads** — type player names in batting order, drag to reorder, swipe to mark © captain / † keeper. Names can be fixed at any time (even mid-match) from the hub.
4. **Start Scoring** — pick striker, non-striker and opening bowler.
5. **Score** — tap 0/1/2/3/4/6, or **Extras** (Wide, No Ball, Bye, Leg Bye, No Ball + Bye/Leg Bye with runs-ran; the 1-run penalty is added for you) or **Wicket** (all dismissal types, batter out, fielder, runs completed, crossed).
6. **Fix anything** — *Undo* removes the last event, *Swap Striker* corrects ends without a ball, tap any ball in the Ball-by-Ball list to edit runs/extras/dismissal or delete it. Change bowler at any time; you are prompted at the end of each over and a bowler cannot exceed the standard max overs.
7. **Innings** — innings ends automatically when overs run out or the side is all out, or end it early (declare) from the menu. Start the next innings from the same menu.
8. **Scorecard** — batting, bowling, extras, fall of wickets and full ball-by-ball, with a text result. Use **Share Scorecard** to send it anywhere. Data never leaves the device unless you share it.

## Design Note

The ordered ball log (`Innings.events`) is the single source of truth. Every
total, figure and scorecard is derived by replaying it in `ScoringEngine`, so
undo / edit / swap can never leave the score inconsistent.
