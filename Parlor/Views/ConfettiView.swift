import SwiftUI

/// One-shot celebratory confetti drawn with Canvas — ~70 pieces tumble down
/// over three seconds, then fade. Parameters per piece are derived from its
/// index, so the animation needs no state beyond the start date.
struct ConfettiView: View {
    private let startDate = Date()
    private let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startDate)
                guard t < 4.5 else { return }
                for i in 0..<70 {
                    var generator = SplitMix64(seed: UInt64(i) &* 0x9E3779B97F4A7C15)
                    let x0 = CGFloat(generator.unit()) * size.width
                    let drift = (CGFloat(generator.unit()) - 0.5) * 120
                    let fall = 180 + CGFloat(generator.unit()) * 220
                    let delay = Double(generator.unit()) * 0.8
                    let spin = (Double(generator.unit()) * 4 + 1) * (generator.unit() > 0.5 ? 1 : -1)
                    let color = colors[i % colors.count]
                    let w = 6 + CGFloat(generator.unit()) * 5
                    let h = 9 + CGFloat(generator.unit()) * 6

                    let local = t - delay
                    guard local > 0 else { continue }
                    let y = -20 + CGFloat(local) * fall
                    guard y < size.height + 30 else { continue }
                    let x = x0 + drift * CGFloat(local) * 0.4
                        + sin(CGFloat(local) * 3 + CGFloat(i)) * 14
                    let alpha = local > 2.8 ? max(0, 1 - (local - 2.8) / 0.8) : 1

                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * spin))
                    piece.opacity = alpha
                    piece.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                               with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Tiny deterministic RNG so every confetti piece gets stable parameters.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
