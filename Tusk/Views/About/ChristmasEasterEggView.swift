import SwiftUI

struct ChristmasEasterEggView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snowflakes: [Snowflake] = ChristmasEasterEggView.makeSnowflakes()

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.13, blue: 0.25)
                .ignoresSafeArea()

            // Animated snowflakes
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    for flake in snowflakes {
                        let progress = (elapsed * flake.speed + flake.offset).truncatingRemainder(dividingBy: 1.0)
                        let x = flake.xFraction * size.width + sin(elapsed * flake.sway + flake.offset * .pi * 2) * 18
                        let y = progress * (size.height + 20) - 10
                        let resolved = ctx.resolve(Text(flake.symbol)
                            .font(.system(size: flake.size))
                            .foregroundStyle(.white.opacity(flake.opacity)))
                        ctx.draw(resolved, at: CGPoint(x: x, y: y))
                    }
                }
            }

            VStack(spacing: 0) {
                Spacer()

                // Tree
                VStack(spacing: 2) {
                    Text("*")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                    Text("^ ^ ^")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("^ ^ ^ ^ ^")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("^ ^ ^ ^ ^ ^ ^")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("^ ^ ^ ^ ^ ^ ^ ^ ^")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("|||")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.15))
                }
                .padding(.bottom, 28)

                // Message
                VStack(spacing: 10) {
                    Text("Merry Christmas!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("May your queries be fast,\nyour indexes never bloat,\nand your vacuums run on time.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("Ho ho ho from the Tusk team.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }
                .padding(.bottom, 36)

                Button("Dismiss") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
                .controlSize(.large)

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 420, height: 480)
    }

    // MARK: - Snowflakes

    private struct Snowflake {
        let xFraction: Double
        let speed: Double
        let offset: Double
        let sway: Double
        let size: Double
        let opacity: Double
        let symbol: String
    }

    private static func makeSnowflakes() -> [Snowflake] {
        let symbols = ["*", "+", "·", "❄"]
        return (0..<40).map { i in
            let rng = Double(i)
            func pseudo(_ seed: Double) -> Double {
                let x = sin(seed * 127.1 + 311.7) * 43758.5453
                return x - floor(x)
            }
            return Snowflake(
                xFraction: pseudo(rng),
                speed: 0.04 + pseudo(rng + 1) * 0.06,
                offset: pseudo(rng + 2),
                sway: 0.5 + pseudo(rng + 3) * 1.5,
                size: 8 + pseudo(rng + 4) * 10,
                opacity: 0.3 + pseudo(rng + 5) * 0.5,
                symbol: symbols[Int(pseudo(rng + 6) * Double(symbols.count))]
            )
        }
    }
}
