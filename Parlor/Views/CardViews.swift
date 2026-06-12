import SwiftUI

/// A playing card with real pip layouts for 2–10, a big center pip for the
/// ace, and framed court cards. Small cards (fanned hands, opponents) fall
/// back to a simpler face that stays legible.
struct CardView: View {
    let card: Card
    var width: CGFloat = 52

    private var ink: Color {
        card.suit.isRed ? Color(red: 0.78, green: 0.1, blue: 0.13) : .black
    }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(colors: [.white, Color(white: 0.93)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) { cornerIndex }
            .overlay(alignment: .bottomTrailing) { cornerIndex.rotationEffect(.degrees(180)) }
            .overlay { centerFace }
            .foregroundStyle(ink)
            .frame(width: width, height: width * 1.45)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1.5)
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
            // Tiny cards: one bold pip reads better than ten specks.
            Text(card.suit.symbol)
                .font(.system(size: width * 0.46))
                .offset(x: width * 0.06, y: width * 0.1)
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

    /// Court cards: an inner frame around a tall rank letter flanked by pips.
    private var courtFace: some View {
        RoundedRectangle(cornerRadius: width * 0.06)
            .strokeBorder(ink.opacity(0.55), lineWidth: 1.2)
            .overlay {
                VStack(spacing: -width * 0.02) {
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.18))
                    Text(card.rank.label)
                        .font(.system(size: width * 0.5, weight: .bold, design: .serif))
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.18))
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(.horizontal, width * 0.24)
            .padding(.vertical, width * 0.26)
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
    case classic, crimson, forest, royal, midnight, fish, koi

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
        }
    }

    /// Emoji motif drawn in the middle (nil = classic suit watermark).
    var motif: String? {
        switch self {
        case .fish: return "🐟"
        case .koi: return "🎏"
        case .midnight: return "🌙"
        default: return nil
        }
    }
}

struct FaceDownCardView: View {
    var width: CGFloat = 52
    /// Fixed style for previews; nil follows the user's chosen back.
    var styleOverride: CardBack? = nil
    @AppStorage(CardBack.storageKey) private var backRaw = CardBack.classic.rawValue

    private var back: CardBack { styleOverride ?? CardBack(rawValue: backRaw) ?? .classic }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(colors: back.colors,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                    .padding(width * 0.07)
            )
            .overlay {
                if let motif = back.motif {
                    Text(motif)
                        .font(.system(size: width * 0.42))
                        .opacity(0.85)
                } else {
                    Image(systemName: "suit.club.fill")
                        .font(.system(size: width * 0.32))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }
            .frame(width: width, height: width * 1.45)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1.5)
    }
}

/// Empty pile slot (Klondike foundations / columns).
struct CardSlotView: View {
    var width: CGFloat = 52
    var label: String = ""

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            .overlay(Text(label).font(.system(size: width * 0.5)).foregroundStyle(.white.opacity(0.35)))
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
            let cardWidth: CGFloat = min(56, max(34, geo.size.width / (CGFloat(count) * 0.52 + 0.6)))
            let step = count > 1 ? min(cardWidth * 0.72, (geo.size.width - cardWidth) / CGFloat(count - 1)) : 0
            let totalWidth = cardWidth + step * CGFloat(count - 1)
            let mid = CGFloat(count - 1) / 2
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                        let isLegal = legal.contains(card)
                        // -1…1 across the fan: tilt and dip toward the edges.
                        let t = mid > 0 ? (CGFloat(index) - mid) / mid : 0
                        let lift: CGFloat = selected.contains(card) ? -18 : (enabled && isLegal ? -8 : 0)
                        CardView(card: card, width: cardWidth)
                            .rotationEffect(.degrees(t * 7), anchor: .bottom)
                            .offset(x: CGFloat(index) * step,
                                    y: lift + t * t * 12)
                            .opacity(!enabled || isLegal || !selected.isEmpty || legal.isEmpty ? 1 : 0.55)
                            .onTapGesture { onTap(card) }
                    }
                }
                .frame(width: totalWidth, height: cardWidth * 1.45 + 20, alignment: .bottomLeading)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 112)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cards)
    }
}

/// Compact stack of card backs for opponents.
struct OpponentHandView: View {
    let count: Int
    var width: CGFloat = 26

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                FaceDownCardView(width: width)
                    .offset(x: CGFloat(i) * width * 0.28)
                    .opacity(count == 0 ? 0 : 1)
            }
        }
        .frame(width: width + width * 0.28 * CGFloat(max(count - 1, 0)), height: width * 1.45)
    }
}

struct SeatBadge: View {
    let name: String
    let isCurrent: Bool
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isCurrent ? Color.yellow : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.footnote.weight(isCurrent ? .bold : .regular))
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.25), in: Capsule())
        .foregroundStyle(.white)
    }
}

extension Color {
    static let tableFelt = Color(red: 0.1, green: 0.4, blue: 0.22)
    static let tableFeltDark = Color(red: 0.06, green: 0.28, blue: 0.15)
}

struct FeltBackground: View {
    /// Card tables get a stitched inlay ring around the play area.
    var inlay: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.tableFelt, .tableFeltDark], startPoint: .top, endPoint: .bottom)
            // Soft table lamp falloff toward the edges.
            RadialGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)],
                           center: .center, startRadius: 40, endRadius: 520)
            if inlay {
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(.white.opacity(0.1),
                                  style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
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
            LinearGradient(colors: [Color(red: 0.1, green: 0.08, blue: 0.22),
                                    Color(red: 0.04, green: 0.03, blue: 0.1)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.25), .clear],
                           center: .top, startRadius: 0, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}
