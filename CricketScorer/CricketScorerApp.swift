import SwiftUI
import SwiftData

@main
struct CricketScorerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Match.self, Player.self, Innings.self])
    }
}
