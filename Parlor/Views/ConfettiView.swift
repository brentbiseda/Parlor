import SwiftUI

/// One-shot celebratory confetti drawn with Canvas — 180 pieces tumble down
/// over six seconds, then fade. Shapes include rectangles, circles, triangles, and stars.
/// Parameters per piece are derived from its index (deterministic, no extra state).
/// Improvements: horizontal wind drift, 6+ distinct colors with gold, 3-tier size variation.
struct ConfettiView: View {
    private let startDate = Date()
    // 18. Color variety: at least 6 distinct colors including gold and accent tones.
    private let colors: [Color] = [
        .red,
        Color(red: 1.0, green: 0.45, blue: 0.1),   // orange
        .yellow,
        Color(red: 1.0, green: 0.84, blue: 0.0),    // gold (improvement 19)
        Color(red: 0.3, green: 0.9, blue: 0.3),     // lime green
        .mint,
        Color(red: 0.2, green: 0.7, blue: 1.0),     // sky blue
        .blue,
        Color(red: 0.65, green: 0.3, blue: 1.0),    // violet
        .pink,
        Color(red: 1.0, green: 0.85, blue: 0.0),    // bright gold
        Color(red: 0.0, green: 0.9, blue: 0.8),     // teal
        Color(red: 1.0, green: 0.35, blue: 0.7),    // hot pink
        Color(red: 0.95, green: 0.95, blue: 0.95),  // near-white
        Color(red: 0.3, green: 0.85, blue: 0.45),   // emerald
        Color(red: 0.9, green: 0.2, blue: 0.5)      // crimson rose
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startDate)
                guard t < 6.5 else { return }
                // 18. Horizontal drift: wind offset accumulated over time.
                let windDrift: CGFloat = sin(CGFloat(t) * 0.4) * 18

                for i in 0..<180 {
                    var generator = SplitMix64(seed: UInt64(i) &* 0x9E3779B97F4A7C15)
                    let x0 = CGFloat(generator.unit()) * size.width
                    // 18. Each particle gets a random per-particle dx (−0.5…0.5 normalised)
                    let particleDx = (CGFloat(generator.unit()) - 0.5)  // -0.5...0.5
                    let drift = (CGFloat(generator.unit()) - 0.5) * 180
                    // 20. Particle size tier (small/medium/large) based on index mod 3.
                    let sizeTier = i % 3  // 0=small, 1=medium, 2=large
                    // Large particles fall ~15% slower for a natural layered look.
                    let fallSpeedMult: CGFloat = sizeTier == 2 ? 0.82 : (sizeTier == 1 ? 0.92 : 1.0)
                    let fall = (140 + CGFloat(generator.unit()) * 300) * fallSpeedMult
                    let delay = Double(generator.unit()) * 1.8
                    let spin = (Double(generator.unit()) * 6 + 1) * (generator.unit() > 0.5 ? 1 : -1)
                    let colorIdx = Int(generator.unit() * Double(colors.count)) % colors.count
                    let color = colors[colorIdx]
                    // 20. Size varies by tier: small/medium/large.
                    let sizeScale: CGFloat = sizeTier == 0 ? 0.65 : (sizeTier == 1 ? 1.0 : 1.45)
                    let w = (5 + CGFloat(generator.unit()) * 8) * sizeScale
                    let h = (7 + CGFloat(generator.unit()) * 10) * sizeScale
                    let shape = Int(generator.unit() * 4)  // 0=rect, 1=circle, 2=triangle, 3=star

                    let local = t - delay
                    guard local > 0 else { continue }
                    let y = -20 + CGFloat(local) * fall
                    guard y < size.height + 40 else { continue }
                    // 18. Horizontal position incorporates particleDx wind drift each frame.
                    let x = x0
                        + drift * CGFloat(local) * 0.4
                        + sin(CGFloat(local) * 2.8 + CGFloat(i)) * 20
                        + particleDx * CGFloat(local) * 24  // wind effect
                        + windDrift * (1 + particleDx)      // global wind wave
                    let alpha = local > 4.0 ? max(0, 1 - (local - 4.0) / 1.2) : 1.0

                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * spin))
                    piece.opacity = alpha

                    switch shape {
                    case 1:
                        piece.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -w / 2, width: w, height: w)),
                                   with: .color(color))
                    case 2:
                        var tri = Path()
                        tri.move(to: CGPoint(x: 0, y: -h / 2))
                        tri.addLine(to: CGPoint(x: w / 2, y: h / 2))
                        tri.addLine(to: CGPoint(x: -w / 2, y: h / 2))
                        tri.closeSubpath()
                        piece.fill(tri, with: .color(color))
                    case 3:
                        piece.fill(starPath(r: w * 0.52, n: 5), with: .color(color))
                    default:
                        piece.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                                   with: .color(color))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func starPath(r: CGFloat, n: Int) -> Path {
        var path = Path()
        let inner = r * 0.4
        for i in 0..<(n * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(n) - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : inner
            let pt = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
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
