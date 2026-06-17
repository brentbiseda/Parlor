import SwiftUI
import UIKit

/// A playing card with real pip layouts for 2–10, a big center pip for the
/// ace, and framed court cards. Small cards (fanned hands, opponents) fall
/// back to a simpler face that stays legible.
struct CardView: View {
    let card: Card
    var width: CGFloat = 52

    private var ink: Color {
        card.suit.isRed ? Color(red: 0.82, green: 0.08, blue: 0.12) : Color(red: 0.08, green: 0.08, blue: 0.10)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(white: 0.975), location: 0.35),
                    .init(color: Color(white: 0.935), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: width * 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.12))
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.75)
            )
            .overlay(alignment: .topLeading) { cornerIndex }
            .overlay(alignment: .bottomTrailing) { cornerIndex.rotationEffect(.degrees(180)) }
            .overlay { centerFace }
            .foregroundStyle(ink)
            .frame(width: width, height: width * 1.45)
            .shadow(color: .black.opacity(0.32), radius: 4, y: 2.5)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
    }

    private var cornerIndex: some View {
        VStack(alignment: .center, spacing: -width * 0.04) {
            Text(card.rank.label)
                .font(.system(size: width * 0.26, weight: .bold, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: width * 0.2))
        }
        .padding(.horizontal, width * 0.06)
        .padding(.vertical, width * 0.05)
    }

    @ViewBuilder
    private var centerFace: some View {
        if width < 44 {
            // Tiny cards: a rank glyph over a suit pip reads better than ten specks.
            VStack(spacing: -width * 0.06) {
                Text(card.rank.label)
                    .font(.system(size: width * 0.4, weight: .heavy, design: .rounded))
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.36))
            }
            .offset(x: width * 0.04, y: width * 0.08)
        } else {
            switch card.rank {
            case .ace:
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.56))
            case .jack, .queen, .king:
                courtFace
            default:
                pipField
            }
        }
    }

    /// Small emblem distinguishing the three court ranks.
    private var courtEmblem: String {
        switch card.rank {
        case .king: return "♔"
        case .queen: return "♕"
        case .jack: return "⚜"
        default: return card.suit.symbol
        }
    }

    /// Court cards: an inner frame around a tall rank letter flanked by pips.
    private var courtFace: some View {
        RoundedRectangle(cornerRadius: width * 0.06)
            .fill(ink.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.06)
                    .strokeBorder(ink.opacity(0.45), lineWidth: 1.0)
            }
            .overlay {
                VStack(spacing: -width * 0.01) {
                    Text(courtEmblem)
                        .font(.system(size: width * 0.2))
                        .opacity(0.9)
                    Text(card.rank.label)
                        .font(.system(size: width * 0.5, weight: .black, design: .serif))
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.19))
                        .rotationEffect(.degrees(180))
                        .opacity(0.85)
                }
            }
            .padding(.horizontal, width * 0.22)
            .padding(.vertical, width * 0.24)
    }

    /// Standard pip arrangements; bottom-half pips render upside down.
    private var pipField: some View {
        GeometryReader { geo in
            let positions = Self.pipPositions[card.rank.rawValue] ?? []
            ForEach(Array(positions.enumerated()), id: \.offset) { _, pip in
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.21))
                    .rotationEffect(.degrees(pip.y > 0.52 ? 180 : 0))
                    .position(x: geo.size.width * pip.x, y: geo.size.height * pip.y)
            }
        }
        .padding(.horizontal, width * 0.2)
        .padding(.vertical, width * 0.24)
    }

    /// Normalized (x, y) pip centers per rank, matching real cards.
    static let pipPositions: [Int: [(x: CGFloat, y: CGFloat)]] = [
        2: [(0.5, 0.0), (0.5, 1.0)],
        3: [(0.5, 0.0), (0.5, 0.5), (0.5, 1.0)],
        4: [(0.12, 0.0), (0.88, 0.0), (0.12, 1.0), (0.88, 1.0)],
        5: [(0.12, 0.0), (0.88, 0.0), (0.5, 0.5), (0.12, 1.0), (0.88, 1.0)],
        6: [(0.12, 0.0), (0.88, 0.0), (0.12, 0.5), (0.88, 0.5), (0.12, 1.0), (0.88, 1.0)],
        7: [(0.12, 0.0), (0.88, 0.0), (0.5, 0.25), (0.12, 0.5), (0.88, 0.5),
            (0.12, 1.0), (0.88, 1.0)],
        8: [(0.12, 0.0), (0.88, 0.0), (0.5, 0.25), (0.12, 0.5), (0.88, 0.5),
            (0.5, 0.75), (0.12, 1.0), (0.88, 1.0)],
        9: [(0.12, 0.0), (0.88, 0.0), (0.12, 0.33), (0.88, 0.33), (0.5, 0.5),
            (0.12, 0.67), (0.88, 0.67), (0.12, 1.0), (0.88, 1.0)],
        10: [(0.12, 0.0), (0.88, 0.0), (0.5, 0.17), (0.12, 0.33), (0.88, 0.33),
             (0.12, 0.67), (0.88, 0.67), (0.5, 0.83), (0.12, 1.0), (0.88, 1.0)],
    ]
}

/// User-selectable card back designs (chosen in solitaire setup, used by
/// every game that shows a face-down card).
enum CardBack: String, CaseIterable, Identifiable {
    case classic, crimson, forest, royal, midnight, fish, koi, coral, dusk

    var id: String { rawValue }
    static let storageKey = "parlor.cardBack"

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .crimson: return "Crimson"
        case .forest: return "Forest"
        case .royal: return "Royal"
        case .midnight: return "Midnight"
        case .fish: return "Fish"
        case .koi: return "Koi Pond"
        case .coral: return "Coral"
        case .dusk: return "Dusk"
        }
    }

    var colors: [Color] {
        switch self {
        case .classic: return [Color(red: 0.22, green: 0.33, blue: 0.65), Color(red: 0.13, green: 0.2, blue: 0.45)]
        case .crimson: return [Color(red: 0.7, green: 0.12, blue: 0.18), Color(red: 0.42, green: 0.05, blue: 0.1)]
        case .forest: return [Color(red: 0.12, green: 0.45, blue: 0.25), Color(red: 0.05, green: 0.27, blue: 0.14)]
        case .royal: return [Color(red: 0.42, green: 0.2, blue: 0.65), Color(red: 0.24, green: 0.1, blue: 0.4)]
        case .midnight: return [Color(red: 0.15, green: 0.17, blue: 0.22), Color(red: 0.05, green: 0.06, blue: 0.09)]
        case .fish: return [Color(red: 0.0, green: 0.45, blue: 0.6), Color(red: 0.0, green: 0.25, blue: 0.4)]
        case .koi: return [Color(red: 0.95, green: 0.5, blue: 0.25), Color(red: 0.7, green: 0.25, blue: 0.1)]
        case .coral: return [Color(red: 0.92, green: 0.38, blue: 0.42), Color(red: 0.62, green: 0.15, blue: 0.28)]
        case .dusk: return [Color(red: 0.42, green: 0.28, blue: 0.58), Color(red: 0.18, green: 0.08, blue: 0.32)]
        }
    }

    /// Emoji motif drawn in the middle (nil = classic suit watermark).
    var motif: String? {
        switch self {
        case .fish: return "🐟"
        case .koi: return "🎏"
        case .midnight: return "🌙"
        case .coral: return "🪸"
        case .dusk: return "🌆"
        default: return nil
        }
    }
}

struct FaceDownCardView: View {
    var width: CGFloat = 52
    /// Fixed style for previews; nil follows the user's chosen back.
    var styleOverride: CardBack? = nil
    /// When true, animates a horizontal gleam sweep over the card face.
    var shimmer: Bool = false
    @AppStorage(CardBack.storageKey) private var backRaw = CardBack.classic.rawValue
    @State private var shimmerOffset: CGFloat = -1.5

    private var back: CardBack { styleOverride ?? CardBack(rawValue: backRaw) ?? .classic }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(
                stops: [
                    .init(color: back.colors[0], location: 0),
                    .init(color: back.colors.last ?? back.colors[0], location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.25), .clear],
                               startPoint: .top, endPoint: .center)
                    .frame(height: width * 0.6)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.12))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.08)
                    .strokeBorder(.white.opacity(0.38), lineWidth: 1.2)
                    .padding(width * 0.09)
            }
            .overlay {
                if let motif = back.motif {
                    Text(motif)
                        .font(.system(size: width * 0.44))
                        .opacity(0.9)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                } else {
                    // Diagonal pinstripe pattern on the inner panel.
                    Canvas { ctx, size in
                        let stripe: CGFloat = width * 0.14
                        let gap: CGFloat = width * 0.09
                        let inset = width * 0.09
                        let clipRect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
                        ctx.clip(to: Path(roundedRect: clipRect, cornerRadius: width * 0.05))
                        var x = -size.height
                        while x < size.width + size.height {
                            let path = Path { p in
                                p.move(to: CGPoint(x: x, y: 0))
                                p.addLine(to: CGPoint(x: x + stripe, y: 0))
                                p.addLine(to: CGPoint(x: x + stripe + size.height, y: size.height))
                                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                                p.closeSubpath()
                            }
                            ctx.fill(path, with: .color(.white.opacity(0.12)))
                            x += stripe + gap
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(.black.opacity(0.15), lineWidth: 0.75)
            )
            .overlay {
                if shimmer {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.35), location: 0.5),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 1, y: 0))
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.12))
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            shimmerOffset = 1.5
                        }
                    }
                }
            }
            .frame(width: width, height: width * 1.45)
            .shadow(color: .black.opacity(0.32), radius: 4, y: 2.5)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
    }
}

/// Empty pile slot (Klondike foundations / columns).
struct CardSlotView: View {
    var width: CGFloat = 52
    var label: String = ""

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(
                colors: [.black.opacity(0.22), .black.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.12)
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.05), .clear],
                        center: .topLeading, startRadius: 0, endRadius: width * 1.2))
            }
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .overlay {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: width * 0.48, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                        .shadow(color: .white.opacity(0.15), radius: 4)
                }
            }
            .frame(width: width, height: width * 1.45)
    }
}

/// The local player's hand, fanned in a gentle arc like cards held at a
/// table. Legal cards lift and brighten; selected cards lift higher.
struct HandView: View {
    let cards: [Card]
    let legal: Set<Card>
    let enabled: Bool
    var selected: Set<Card> = []
    let onTap: (Card) -> Void

    var body: some View {
        GeometryReader { geo in
            let count = max(cards.count, 1)
            let cardWidth: CGFloat = min(58, max(34, geo.size.width / (CGFloat(count) * 0.52 + 0.6)))
            let step = count > 1 ? min(cardWidth * 0.72, (geo.size.width - cardWidth) / CGFloat(count - 1)) : 0
            let totalWidth = cardWidth + step * CGFloat(count - 1)
            let mid = CGFloat(count - 1) / 2
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                        let isLegal = legal.contains(card)
                        let isSelected = selected.contains(card)
                        let t = mid > 0 ? (CGFloat(index) - mid) / mid : 0
                        let lift: CGFloat = isSelected ? -22 : (enabled && isLegal ? -10 : 0)
                        CardView(card: card, width: cardWidth)
                            .rotationEffect(.degrees(t * 7), anchor: .bottom)
                            .offset(x: CGFloat(index) * step,
                                    y: lift + t * t * 10)
                            .opacity(!enabled || isLegal || !selected.isEmpty || legal.isEmpty ? 1 : 0.45)
                            .overlay(alignment: .top) {
                                if enabled && isLegal && !isSelected {
                                    RoundedRectangle(cornerRadius: cardWidth * 0.12)
                                        .strokeBorder(Color.yellow.opacity(0.65), lineWidth: 2)
                                        .frame(width: cardWidth, height: cardWidth * 1.45)
                                        .allowsHitTesting(false)
                                }
                                if isSelected {
                                    RoundedRectangle(cornerRadius: cardWidth * 0.12)
                                        .strokeBorder(Color.green, lineWidth: 2.5)
                                        .frame(width: cardWidth, height: cardWidth * 1.45)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: cardWidth * 0.34))
                                                .foregroundStyle(.white, .green)
                                                .offset(x: cardWidth * 0.12, y: -cardWidth * 0.12)
                                        }
                                        .allowsHitTesting(false)
                                }
                            }
                            .shadow(
                                color: isSelected ? .yellow.opacity(0.55) : (enabled && isLegal ? .yellow.opacity(0.22) : .clear),
                                radius: isSelected ? 10 : 6, y: isSelected ? 3 : 1)
                            .onTapGesture {
                                if enabled && legal.contains(card) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                onTap(card)
                            }
                            .zIndex(isSelected ? 10 : Double(index))
                    }
                }
                .frame(width: totalWidth, height: cardWidth * 1.45 + 22, alignment: .bottomLeading)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 116)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: cards)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: selected)
        .animation(.easeInOut(duration: 0.25), value: enabled)
        .saturation(enabled ? 1.0 : 0.55)
        .brightness(enabled ? 0 : -0.08)
    }
}

/// Compact stack of card backs for opponents.
struct OpponentHandView: View {
    let count: Int
    var width: CGFloat = 26

    var body: some View {
        if count == 0 {
            // Empty hand — show a faint slot so the layout doesn't collapse.
            RoundedRectangle(cornerRadius: width * 0.12)
                .strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: width, height: width * 1.45)
                .opacity(0.6)
        } else {
            let visible = min(count, 8)
            let spreadFactor: CGFloat = visible > 5 ? 0.22 : 0.30
            let tiltScale: Double = visible > 5 ? 2.0 : 3.0
            ZStack(alignment: .leading) {
                ForEach(0..<visible, id: \.self) { i in
                    let spread = CGFloat(i) * width * spreadFactor
                    let tilt = Double(i - max(visible - 1, 0) / 2) * tiltScale
                    FaceDownCardView(width: width)
                        .rotationEffect(.degrees(tilt), anchor: .bottom)
                        .offset(x: spread)
                        .zIndex(Double(i))
                }
                if count > 8 {
                    Text("+\(count - 8)")
                        .font(.system(size: width * 0.32, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, width * 0.22)
                        .padding(.vertical, width * 0.1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .offset(x: CGFloat(visible - 1) * width * spreadFactor + width * 0.85,
                                y: -width * 0.1)
                } else if count <= 2 {
                    // Low-card alarm: highlight an opponent close to going out.
                    Text("\(count)")
                        .font(.system(size: width * 0.34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: width * 0.5, height: width * 0.5)
                        .background(Color.red.opacity(0.92), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        .offset(x: CGFloat(visible - 1) * width * spreadFactor + width * 0.7,
                                y: -width * 0.22)
                }
            }
            .frame(width: width + width * spreadFactor * CGFloat(max(visible - 1, 0)) + (count > 8 ? width * 1.2 : 0),
                   height: width * 1.55)
        }
    }
}

/// Compact player circle for the turn-indicator strip in TableView.
/// The active player gets a pulsing green ring; the "you" seat gets a teal dot.
struct PlayerAvatarCell: View {
    let name: String
    let isCurrent: Bool
    let isYou: Bool
    var isBot: Bool = false
    @State private var pulse: CGFloat = 0

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isCurrent {
                    Circle()
                        .strokeBorder(Color.green.opacity(0.55 * (1 - pulse)), lineWidth: 3)
                        .frame(width: 34, height: 34)
                        .scaleEffect(1 + pulse * 0.35)
                }
                Circle()
                    .fill(isCurrent
                          ? LinearGradient(colors: [Color.green.opacity(0.45), Color.green.opacity(0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                if isCurrent {
                    Circle()
                        .strokeBorder(Color.green, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
                Image(systemName: isYou ? "person.fill" : "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrent ? .white : .white.opacity(0.5))
            }
            .overlay(alignment: .topTrailing) {
                if isYou {
                    Circle()
                        .fill(Color.teal)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
            }
            Text(name)
                .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.45))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            // Micro-label: "You" for local human, "🤖" for bots
            if isYou {
                Text("You")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.teal.opacity(0.9))
            } else if isBot {
                Text("🤖")
                    .font(.system(size: 7))
            }
        }
        .onAppear {
            guard isCurrent else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = 1.0
            }
        }
        .onChange(of: isCurrent) { _, now in
            pulse = 0
            if now {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = 1.0
                }
            }
        }
    }
}

struct SeatBadge: View {
    let name: String
    let isCurrent: Bool
    var detail: String? = nil
    @State private var pulse: CGFloat = 0.6

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                ZStack {
                    if isCurrent {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 9, height: 9)
                            .scaleEffect(1 + pulse * 0.8)
                            .opacity(1 - pulse)
                    }
                    Circle()
                        .fill(isCurrent
                              ? LinearGradient(colors: [.yellow, Color(red: 1.0, green: 0.75, blue: 0.1)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.2)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 9, height: 9)
                }
                Text(name)
                    .font(.footnote.weight(isCurrent ? .bold : .medium))
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            isCurrent
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 0.55, green: 0.44, blue: 0.0).opacity(0.55),
                             Color.black.opacity(0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(.black.opacity(0.3)),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                isCurrent
                    ? LinearGradient(colors: [Color.yellow.opacity(0.7), Color.yellow.opacity(0.3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.1), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.2
            )
        )
        .shadow(color: isCurrent ? .yellow.opacity(0.45) : .clear, radius: 10)
        .foregroundStyle(.white)
        .onAppear {
            guard isCurrent else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = 1.0
            }
        }
    }
}

extension Color {
    static let tableFelt = Color(red: 0.1, green: 0.4, blue: 0.22)
    static let tableFeltDark = Color(red: 0.06, green: 0.28, blue: 0.15)
}

/// User-selectable table felt, shared by every card/board/tile table.
enum FeltTheme: String, CaseIterable, Identifiable {
    case classic, midnight, burgundy, charcoal

    static let storageKey = "parlor.felt"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Casino Green"
        case .midnight: return "Midnight Blue"
        case .burgundy: return "Burgundy"
        case .charcoal: return "Charcoal"
        }
    }

    var colors: [Color] {
        switch self {
        case .classic: return [.tableFelt, .tableFeltDark]
        case .midnight: return [Color(red: 0.09, green: 0.2, blue: 0.4),
                                Color(red: 0.04, green: 0.1, blue: 0.22)]
        case .burgundy: return [Color(red: 0.42, green: 0.1, blue: 0.15),
                                Color(red: 0.24, green: 0.05, blue: 0.08)]
        case .charcoal: return [Color(red: 0.22, green: 0.23, blue: 0.25),
                                Color(red: 0.1, green: 0.1, blue: 0.12)]
        }
    }
}

struct FeltBackground: View {
    /// Card tables get a stitched inlay ring around the play area.
    var inlay: Bool = false
    @AppStorage(FeltTheme.storageKey) private var feltRaw = FeltTheme.classic.rawValue

    private var theme: FeltTheme { FeltTheme(rawValue: feltRaw) ?? .classic }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom)
            // Subtle weave texture simulating felt fiber.
            Canvas { ctx, size in
                let spacing: CGFloat = 3.5
                var gen = SplitMix64(seed: 0xFE175EED)
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        let alpha = 0.025 + Double(gen.unit()) * 0.03
                        let dot = CGRect(x: x + Double(gen.unit()) * 1.5 - 0.75,
                                         y: y + Double(gen.unit()) * 1.5 - 0.75,
                                         width: 1, height: 1)
                        ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(alpha)))
                        x += spacing
                    }
                    y += spacing
                }
            }
            .blendMode(.overlay)
            RadialGradient(
                colors: [.white.opacity(0.20), .clear],
                center: .center, startRadius: 0, endRadius: 240)
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: .center, startRadius: 220, endRadius: 620)
            LinearGradient(
                colors: [.black.opacity(0.32), .clear, .clear, .black.opacity(0.28)],
                startPoint: .top, endPoint: .bottom)
            LinearGradient(
                colors: [.black.opacity(0.20), .clear, .black.opacity(0.20)],
                startPoint: .leading, endPoint: .trailing)
            if inlay {
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.07)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                    )
                    .padding(18)
                    .padding(.vertical, 40)
            }
        }
        .ignoresSafeArea()
    }
}

struct ArcadeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.09, green: 0.07, blue: 0.21), location: 0),
                    .init(color: Color(red: 0.06, green: 0.05, blue: 0.16), location: 0.5),
                    .init(color: Color(red: 0.02, green: 0.02, blue: 0.08), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.55, green: 0.22, blue: 0.85).opacity(0.32), .clear],
                           center: .top, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Color(red: 0.12, green: 0.35, blue: 0.80).opacity(0.20), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 400)
            LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.22)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
