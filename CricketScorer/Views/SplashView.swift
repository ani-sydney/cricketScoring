import SwiftUI

/// Cricket palette: pitch green, outfield stripe, ball red, stump gold.
enum CricketTheme {
    static let pitchGreen = Color(red: 0.05, green: 0.30, blue: 0.19)
    static let outfieldGreen = Color(red: 0.09, green: 0.45, blue: 0.28)
    static let turfLight = Color(red: 0.85, green: 0.93, blue: 0.86)
    static let ballRed = Color(red: 0.72, green: 0.11, blue: 0.14)
    static let stumpGold = Color(red: 0.96, green: 0.77, blue: 0.26)
    static let creaseWhite = Color.white
}

/// Branding shown at cold start: a red ball bounces in, hits gold stumps,
/// then the app title settles. Respects Reduce Motion.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ballOffset: CGFloat = -170
    @State private var ballOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var stumpsShake: CGFloat = 0

    var body: some View {
        ZStack {
            CricketTheme.pitchGreen.ignoresSafeArea()
            // Mown stripes
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(i.isMultiple(of: 2) ? CricketTheme.outfieldGreen.opacity(0.55)
                                                 : CricketTheme.pitchGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    // Crease line
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CricketTheme.creaseWhite.opacity(0.9))
                        .frame(width: 210, height: 5)
                        .offset(y: 58)
                    // Stumps
                    HStack(spacing: 9) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(CricketTheme.stumpGold)
                                .frame(width: 9, height: 74)
                        }
                    }
                    .offset(x: stumpsShake, y: 16)
                    // Bails
                    HStack(spacing: 14) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(CricketTheme.stumpGold)
                                .frame(width: 22, height: 5)
                        }
                    }.offset(y: -24)
                    // Ball
                    ZStack {
                        Circle().fill(CricketTheme.ballRed).frame(width: 46, height: 46)
                        // Seam
                        Path { path in
                            path.move(to: CGPoint(x: 10, y: 6))
                            path.addCurve(to: CGPoint(x: 10, y: 40),
                                          control1: CGPoint(x: 22, y: 14),
                                          control2: CGPoint(x: 22, y: 32))
                            path.move(to: CGPoint(x: 36, y: 6))
                            path.addCurve(to: CGPoint(x: 36, y: 40),
                                          control1: CGPoint(x: 24, y: 14),
                                          control2: CGPoint(x: 24, y: 32))
                        }
                        .stroke(.white.opacity(0.85), lineWidth: 1.6)
                        .frame(width: 46, height: 46)
                    }
                    .offset(x: ballOffset, y: 34)
                    .opacity(ballOpacity)
                }
                .frame(height: 170)

                VStack(spacing: 7) {
                    Text("CRICKET SCORER")
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(1.2)
                    Text("Ball-by-ball scoring • On-device only")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .opacity(titleOpacity)
            }
        }
        .onAppear {
            if reduceMotion {
                ballOffset = -52; ballOpacity = 1; titleOpacity = 1
                return
            }
            withAnimation(.easeIn(duration: 0.55)) {
                ballOffset = -52; ballOpacity = 1
            }
            withAnimation(.easeInOut(duration: 0.12).delay(0.55).repeatCount(3, autoreverses: true)) {
                stumpsShake = 3
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.5)) {
                titleOpacity = 1
            }
        }
    }
}
