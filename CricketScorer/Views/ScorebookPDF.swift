import SwiftUI
import UIKit

/// Generates an SCA Score Book-style PDF: one landscape sheet per innings
/// (header, batting table, sundries, fall of wickets, bowling analysis),
/// followed by a match summary page covering both teams and all innings.
/// SCA logo is not reproduced; layout and headings follow the sheet.
enum ScorebookExporter {

    static func makePDF(match: Match, day: Int, isFinalDay: Bool) -> Data {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let names = Dictionary(uniqueKeysWithValues: match.players.map {
            ($0.id, $0.name.isEmpty ? "Player \($0.battingOrder + 1)" : $0.name)
        })
        return renderer.pdfData { context in
            for inn in match.inningsList.sorted(by: { $0.inningsNumber < $1.inningsNumber }) {
                context.beginPage()
                drawInningsSheet(match: match, innings: inn, names: names,
                                 day: day, isFinalDay: isFinalDay,
                                 in: context.cgContext, page: page)
            }
            context.beginPage()
            drawSummary(match: match, names: names, day: day,
                        isFinalDay: isFinalDay, in: context.cgContext, page: page)
        }
    }

    // MARK: - Drawing helpers

    private static func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 8,
                             bold: Bool = false, color: UIColor = .black,
                             align: NSTextAlignment = .left, width: CGFloat = 400) {
        let font: UIFont = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let para = NSMutableParagraphStyle(); para.alignment = align; para.lineBreakMode = .byTruncatingTail
        var a = attrs; a[.paragraphStyle] = para
        (s as NSString).draw(in: CGRect(x: x, y: y, width: width, height: size + 5), withAttributes: a)
    }
    private static func box(_ ctx: CGContext, _ r: CGRect) {
        ctx.setStrokeColor(UIColor.black.cgColor); ctx.setLineWidth(0.7); ctx.stroke(r)
    }
    private static func line(_ ctx: CGContext, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        ctx.setStrokeColor(UIColor.black.cgColor); ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x1, y: y1)); ctx.addLine(to: CGPoint(x: x2, y: y2)); ctx.strokePath()
    }

    // MARK: - Innings sheet (SCA layout)

    private static func drawInningsSheet(match: Match, innings: Innings, names: [UUID: String],
                                         day: Int, isFinalDay: Bool,
                                         in ctx: CGContext, page: CGRect) {
        let m: CGFloat = 24
        let w = page.width - m * 2
        let state = ScoringEngine.replay(events: innings.events,
            playersPerSide: match.playersPerSide, oversPerInnings: match.oversPerInnings,
            ballsPerOver: match.ballsPerOver, names: names)
        let batting = match.players(for: innings.battingSide)
        let bowling = match.players(for: innings.battingSide.other)

        box(ctx, CGRect(x: m, y: m, width: w, height: 52))
        text("SCORE BOOK", x: m, y: m + 6, size: 19, bold: true, align: .center, width: w)
        text("COMPETITION \(match.title)", x: m + 8, y: m + 32, size: 8, width: 240)
        text("MATCH AGAINST \(match.teamName(innings.battingSide.other))", x: m + 250, y: m + 32, size: 8, width: 250)
        text("DATE \(match.matchDate.formatted(date: .abbreviated, time: .omitted))  •  DAY \(day)\(isFinalDay ? " (FINAL)" : "")",
             x: m + 510, y: m + 32, size: 8, width: 280)
        text("TOSS WON BY \(match.teamName(match.tossWinner)) — elected to \(match.tossDecision.rawValue)  •  PLAYED AT \(match.venue)  •  INNINGS OF \(match.teamName(innings.battingSide)) (Innings \(innings.inningsNumber))",
             x: m + 8, y: m + 43, size: 8, width: w - 16)

        // Batting table
        let top = m + 84
        let cols: [(String, CGFloat)] = [("№", 24), ("BATSMEN", 150), ("RUNS AS SCORED", 190),
                                         ("HOW OUT", 165), ("BOWLER", 120), ("BALLS", 42), ("4s/6s", 42), ("TOTALS", 61)]
        var x = m
        box(ctx, CGRect(x: m, y: top, width: w, height: 16))
        for (title, cw) in cols {
            text(title, x: x + 3, y: top + 4, size: 7, bold: true, width: cw - 4)
            line(ctx, x + cw, top, x + cw, top + 16); x += cw
        }
        // Scoring shots per batter, derived from the ball log.
        var shots: [UUID: [String]] = [:]
        for e in innings.events where !e.isSwapMarker {
            if let st = e.strikerID, e.extra != ExtraKind.wide { shots[st, default: []].append(e.symbol) }
        }
        var y = top + 16
        let rowH: CGFloat = 16
        for (i, p) in batting.enumerated() {
            box(ctx, CGRect(x: m, y: y, width: w, height: rowH))
            var cx = m
            let f = state.batterFigures[p.id]
            let values: [String] = [
                "\(i + 1)",
                p.name.isEmpty ? "Player \(p.battingOrder + 1)" : p.name,
                (shots[p.id] ?? []).joined(separator: " "),
                f?.hasBatted == true ? (f?.dismissalText ?? "") : "did not bat",
                "", // bowler column filled by dismissal text where relevant
                f?.hasBatted == true ? "\(f?.balls ?? 0)" : "",
                f?.hasBatted == true ? "\(f?.fours ?? 0)/\(f?.sixes ?? 0)" : "",
                f?.hasBatted == true ? "\(f?.runs ?? 0)" : "",
            ]
            for (idx, v) in values.enumerated() {
                text(v, x: cx + 3, y: y + 4, size: 7.5, bold: idx == 7, width: cols[idx].1 - 5)
                cx += cols[idx].1
                if cx < m + w { line(ctx, cx, y, cx, y + rowH) }
            }
            y += rowH
        }
        // Sundries + total
        let extrasTotal = state.extrasBreakdown.values.reduce(0, +)
        let sundries = state.extrasBreakdown.map { "\($0.key) \($0.value)" }.sorted().joined(separator: "   ")
        box(ctx, CGRect(x: m, y: y, width: w, height: 16))
        text("SUNDRIES  \(sundries)", x: m + 4, y: y + 4, size: 8, width: 420)
        text("TOTAL SUNDRIES \(extrasTotal)", x: m + 430, y: y + 4, size: 8, bold: true, width: 160)
        text("TOTAL SCORE  \(state.totalRuns) for \(state.wickets)  (\(state.oversText) overs)",
             x: m + 590, y: y + 4, size: 8.5, bold: true, width: 200)
        y += 22

        // Fall of wickets
        text("SCORE AT EACH F.O.W.", x: m, y: y, size: 8, bold: true, width: 200)
        let fow = state.fallOfWickets.map { "\($0.score) (\($0.over))" }.joined(separator: "    ")
        text(fow.isEmpty ? "—" : fow, x: m + 130, y: y, size: 8, width: w - 130)
        y += 16
        text("RESULT / NOT OUT: " + batting.filter {
            let f = state.batterFigures[$0.id]; return f?.hasBatted == true && f?.isOut != true
        }.map { "\(names[$0.id] ?? "") \(state.batterFigures[$0.id]?.runs ?? 0)*" }.joined(separator: ", "),
             x: m, y: y, size: 8, width: w)
        y += 20

        // Bowling analysis
        text("BOWLING ANALYSIS", x: m, y: y, size: 9, bold: true, width: 200)
        y += 14
        let bCols: [(String, CGFloat)] = [("BOWLER", 170), ("OVERS", 70), ("MAIDENS", 80),
                                          ("WIDES", 70), ("NO BALLS", 80), ("WICKETS", 80), ("RUNS", 70)]
        let gridW = w - bCols.map(\.1).reduce(0, +)
        var bx = m
        box(ctx, CGRect(x: m, y: y, width: w, height: 15))
        for (title, cw) in bCols {
            text(title, x: bx + 3, y: y + 4, size: 7, bold: true, width: cw - 4); bx += cw
        }
        text("RUNS PER OVER →", x: bx + 3, y: y + 4, size: 7, bold: true, width: gridW)
        y += 15
        let perOver = overRuns(innings: innings, ballsPerOver: match.ballsPerOver)
        for p in bowling {
            guard let f = state.bowlerFigures[p.id] else { continue }
            box(ctx, CGRect(x: m, y: y, width: w, height: 15))
            let vals = [names[p.id] ?? "", f.oversText, "\(maidens(innings: innings, bowlerID: p.id, ballsPerOver: match.ballsPerOver))",
                        "\(f.wides)", "\(f.noBalls)", "\(f.wickets)", "\(f.runs)"]
            var cx = m
            for (idx, v) in vals.enumerated() {
                text(v, x: cx + 3, y: y + 4, size: 7.5, width: bCols[idx].1 - 5); cx += bCols[idx].1
            }
            let overs = perOver[p.id] ?? []
            if !overs.isEmpty, gridW > 20 {
                let cell = min(22, gridW / CGFloat(max(overs.count, 1)))
                for (oi, r) in overs.enumerated() {
                    text("\(r)", x: cx + CGFloat(oi) * cell + 2, y: y + 4, size: 7, width: cell)
                }
            }
            y += 15
        }
        y += 10
        line(ctx, m, y, m + w, y)
        text("SCORERS NAMES ______________________        UMPIRES NAMES ______________________        UMPIRES SIGNATURES ______________________",
             x: m, y: y + 6, size: 8, width: w)
        text("Exported from Cricket Scorer (on-device). Day \(day)\(isFinalDay ? " — final day" : ""). Innings \(innings.inningsNumber) of \(match.teamName(innings.battingSide)).",
             x: m, y: page.height - 34, size: 7, color: .gray, width: w)
    }

    // MARK: - Summary page

    private static func drawSummary(match: Match, names: [UUID: String], day: Int,
                                    isFinalDay: Bool, in ctx: CGContext, page: CGRect) {
        let m: CGFloat = 36
        let w = page.width - m * 2
        text("MATCH SUMMARY — END OF DAY \(day)\(isFinalDay ? " (FINAL)" : "")",
             x: m, y: 40, size: 17, bold: true, width: w)
        text("\(match.teamAName) v \(match.teamBName)  •  \(match.matchDate.formatted(date: .abbreviated, time: .omitted))  •  \(match.venue)",
             x: m, y: 66, size: 10, width: w)
        text("Toss: \(match.teamName(match.tossWinner)) won and elected to \(match.tossDecision.rawValue). Format: \(match.oversPerInnings) overs, \(match.playersPerSide)-a-side, \(match.inningsPerTeam) innings per team.",
             x: m, y: 84, size: 9, color: .darkGray, width: w)
        var y: CGFloat = 116
        for inn in match.inningsList.sorted(by: { $0.inningsNumber < $1.inningsNumber }) {
            let state = ScoringEngine.replay(events: inn.events,
                playersPerSide: match.playersPerSide, oversPerInnings: match.oversPerInnings,
                ballsPerOver: match.ballsPerOver, names: names)
            box(ctx, CGRect(x: m, y: y, width: w, height: 22))
            text("Innings \(inn.inningsNumber): \(match.teamName(inn.battingSide))  \(state.totalRuns)/\(state.wickets)  (\(state.oversText) overs)\(inn.isCompleted ? "  — closed" : "  — in progress")",
                 x: m + 8, y: y + 6, size: 11, bold: true, width: w - 16)
            y += 30
            for p in match.players(for: inn.battingSide) {
                if let f = state.batterFigures[p.id], f.hasBatted {
                    text("\(names[p.id] ?? "")  \(f.dismissalText)  \(f.runs) (\(f.balls))",
                         x: m + 14, y: y, size: 9, width: w - 28); y += 14
                }
            }
            for p in match.players(for: inn.battingSide.other) {
                if let f = state.bowlerFigures[p.id] {
                    text("Bowling: \(names[p.id] ?? "")  \(f.oversText)-\(f.wickets)/\(f.runs)",
                         x: m + 14, y: y, size: 9, color: .darkGray, width: w - 28); y += 14
                }
            }
            y += 12
        }
        line(ctx, m, y, m + w, y); y += 12
        text(resultLine(match: match, names: names), x: m, y: y, size: 12, bold: true, width: w)
        y += 22
        text(isFinalDay ? "Match finished. Scorebook exported at end of match."
                        : "Day \(day) finished. This scorebook can be exported again on the next day — it always reflects the innings played so far.",
             x: m, y: y, size: 9, color: .darkGray, width: w)
    }

    private static func resultLine(match: Match, names: [UUID: String]) -> String {
        let sorted = match.inningsList.sorted { $0.inningsNumber < $1.inningsNumber }
        guard sorted.count >= 2, sorted[1].isCompleted else {
            if let last = sorted.last {
                let s = ScoringEngine.replay(events: last.events, playersPerSide: match.playersPerSide,
                    oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: names)
                return "In progress: \(match.teamName(last.battingSide)) \(s.totalRuns)/\(s.wickets)"
            }
            return "No innings yet."
        }
        func total(_ inn: Innings) -> Int {
            ScoringEngine.replay(events: inn.events, playersPerSide: match.playersPerSide,
                oversPerInnings: match.oversPerInnings, ballsPerOver: match.ballsPerOver, names: names).totalRuns
        }
        // Aggregate per team across all their innings.
        var agg: [TeamSide: Int] = [:]
        for inn in sorted { agg[inn.battingSide, default: 0] += total(inn) }
        let a = agg[TeamSide.a] ?? 0, b = agg[TeamSide.b] ?? 0
        if a == b { return "Result: match tied (\(match.teamAName) \(a), \(match.teamBName) \(b))" }
        let winner = a > b ? match.teamAName : match.teamBName
        return "Result: \(winner) won — \(match.teamAName) \(a), \(match.teamBName) \(b)"
    }

    // MARK: - Over splits

    private static func overRuns(innings: Innings, ballsPerOver: Int) -> [UUID: [Int]] {
        var result: [UUID: [Int]] = [:]
        var legalInOver = 0
        var currentBowler: UUID?
        var currentRuns = 0
        func flush() {
            guard let b = currentBowler else { return }
            result[b, default: []].append(currentRuns)
            currentRuns = 0
        }
        for e in innings.events where !e.isSwapMarker {
            if currentBowler == nil { currentBowler = e.bowlerID }
            if e.bowlerID != currentBowler, legalInOver == 0 { currentBowler = e.bowlerID }
            currentRuns += e.batterRuns + ((e.extra == ExtraKind.wide || e.extra == ExtraKind.noBall
                || e.extra == ExtraKind.noBallBye || e.extra == ExtraKind.noBallLegBye) ? e.extraRunsTotal : 0)
            if e.isLegal {
                legalInOver += 1
                if legalInOver == ballsPerOver { flush(); legalInOver = 0; currentBowler = nil }
            }
        }
        if legalInOver > 0 || currentRuns > 0 { flush() }
        return result
    }

    private static func maidens(innings: Innings, bowlerID: UUID, ballsPerOver: Int) -> Int {
        (overRuns(innings: innings, ballsPerOver: ballsPerOver)[bowlerID] ?? [])
            .filter { $0 == 0 }.count
    }
}

/// UIKit share sheet (Messages, Mail, AirDrop, Files, Print, …).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
