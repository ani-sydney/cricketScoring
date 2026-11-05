import SwiftUI

/// Shows the cricket splash briefly at cold start, then the match list.
/// Uses only SF Symbols and drawn shapes — no external images.
struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some View {
        ZStack {
            MatchListView()
                .opacity(showSplash ? 0 : 1)
            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.9))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                showSplash = false
            }
        }
    }
}
