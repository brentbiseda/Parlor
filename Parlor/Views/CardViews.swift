import SwiftUI

struct CardView: View {
    let card: Card
    var width: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(LinearGradient(colors: [.white, Color(white: 0.93)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.12)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(card.rank.label)
                        .font(.system(size: width * 0.32, weight: .semibold, design: .rounded))
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.28))
                }
                .padding(width * 0.08)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.42))
                    .padding(width * 0.08)
            }
            .foregroundStyle(card.suit.isRed ? Color(red: 0.78, green: 0.1, blue: 0.13) : .black)
            .frame(width: width, height: width * 1.45)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1.5)
    }
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

/// The local player's fanned hand. Legal cards lift and brighten.
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
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                        let isLegal = legal.contains(card)
                        CardView(card: card, width: cardWidth)
                            .offset(x: CGFloat(index) * step,
                                    y: selected.contains(card) ? -18 : (enabled && isLegal ? -8 : 0))
                            .opacity(!enabled || isLegal || !selected.isEmpty || legal.isEmpty ? 1 : 0.55)
                            .onTapGesture { onTap(card) }
                    }
                }
                .frame(width: totalWidth, height: cardWidth * 1.45 + 20, alignment: .bottomLeading)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 110)
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
    var body: some View {
        ZStack {
            LinearGradient(colors: [.tableFelt, .tableFeltDark], startPoint: .top, endPoint: .bottom)
            // Soft table lamp falloff toward the edges.
            RadialGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.25)],
                           center: .center, startRadius: 40, endRadius: 520)
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
