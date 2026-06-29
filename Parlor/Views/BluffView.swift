import SwiftUI

struct BluffView: View {
    @ObservedObject var session: GameSession
    @State private var draftText = ""
    @FocusState private var textFieldFocused: Bool

    var game: BluffGame? { session.game?.engine as? BluffGame }

    var body: some View {
        if let g = game {
            if g.isOver {
                resultScreen(g)
            } else {
                gameScreen(g)
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Game screen

    private func gameScreen(_ g: BluffGame) -> some View {
        VStack(spacing: 0) {
            progressHeader(g)
            switch g.phase {
            case .defining:  definingPhase(g)
            case .voting:    votingPhase(g)
            case .revealing: revealPhase(g)
            case .over:      EmptyView()
            }
        }
        .onChange(of: g.currentRound) { _, _ in draftText = "" }
        .onChange(of: g.phase) { _, p in if p == .defining { draftText = "" } }
    }

    // MARK: - Progress header

    private func progressHeader(_ g: BluffGame) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Round \(g.currentRound + 1) of \(BluffGame.roundsPerGame)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                phaseChip(g.phase)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(g.currentRound) / CGFloat(BluffGame.roundsPerGame), height: 5)
                        .animation(.easeInOut(duration: 0.4), value: g.currentRound)
                }
            }.frame(height: 5)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private func phaseChip(_ phase: BluffGame.Phase) -> some View {
        let (label, color): (String, Color) = {
            switch phase {
            case .defining:  return ("✏️ Define", .purple)
            case .voting:    return ("🎭 Vote", .indigo)
            case .revealing: return ("💡 Reveal", .orange)
            case .over:      return ("", .clear)
            }
        }()
        return Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.75))
    }

    // MARK: - Defining phase

    private func definingPhase(_ g: BluffGame) -> some View {
        let isMyTurn = session.localHumanSeats.contains(g.currentActor)
        return VStack(spacing: 14) {
            if let word = g.currentWord {
                wordCard(word, phase: g.phase)
            }
            Spacer(minLength: 6)

            if isMyTurn {
                VStack(spacing: 10) {
                    Text("P\(g.currentActor + 1) — write a fake definition to fool others")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                        .multilineTextAlignment(.center)
                    TextField("Make it convincing…", text: $draftText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.purple.opacity(0.5), lineWidth: 1.5))
                        .focused($textFieldFocused)
                        .onAppear { textFieldFocused = true }
                    Button {
                        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        session.submit(.bluff(.define(text)))
                        draftText = ""
                        textFieldFocused = false
                    } label: {
                        Label("Submit Definition", systemImage: "theatermasks.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? AnyShapeStyle(.white.opacity(0.1))
                                    : AnyShapeStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)),
                                in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressableTileStyle())
                    .foregroundStyle(.white)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
            } else {
                waitingCard("Waiting for P\(g.currentActor + 1) to write a fake definition…")
            }
            Spacer(minLength: 4)
            scoreRow(g)
        }
    }

    // MARK: - Voting phase

    private func votingPhase(_ g: BluffGame) -> some View {
        let isMyTurn = session.localHumanSeats.contains(g.currentActor)
        let displayed = g.displayedAnswers(for: g.currentRound)
        let votableIndices = g.votableIndices
        return VStack(spacing: 12) {
            if let word = g.currentWord {
                wordCard(word, phase: g.phase)
            }
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Text(isMyTurn ? "WHICH ONE IS THE REAL DEFINITION?" : "P\(g.currentActor + 1) IS DECIDING…")
                    .font(.system(size: 10, weight: .black)).kerning(2)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                ForEach(0..<displayed.count, id: \.self) { idx in
                    let item = displayed[idx]
                    let canVote = isMyTurn && votableIndices.contains(idx)
                    Button {
                        guard canVote else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        session.submit(.bluff(.vote(idx)))
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.label)
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(canVote ? .purple : .white.opacity(0.35))
                                .frame(width: 20)
                            Text(item.text.isEmpty ? "…" : item.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(canVote ? 1 : 0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(4)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(canVote ? Color.purple.opacity(0.12) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(canVote ? Color.purple.opacity(0.5) : Color.white.opacity(0.06), lineWidth: canVote ? 1.5 : 0.75))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canVote)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 4)
            scoreRow(g)
        }
    }

    // MARK: - Reveal phase

    private func revealPhase(_ g: BluffGame) -> some View {
        let displayed = g.displayedAnswers(for: g.currentRound)
        let votes = g.votes
        return VStack(spacing: 12) {
            if let word = g.currentWord {
                wordCard(word, phase: g.phase)
            }
            Spacer(minLength: 4)
            VStack(spacing: 7) {
                Text("WHO FOOLED WHOM?")
                    .font(.system(size: 10, weight: .black)).kerning(2)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(0..<displayed.count, id: \.self) { idx in
                    let item = displayed[idx]
                    let isReal = item.seat == -1
                    let fooledCount = votes.filter { $0 == idx }.count
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.label)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(isReal ? .green : .white.opacity(0.5))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text.isEmpty ? "(no definition)" : item.text)
                                .font(.system(size: 14, weight: isReal ? .bold : .regular))
                                .foregroundStyle(isReal ? .white : .white.opacity(0.7))
                                .lineLimit(4)
                            if isReal {
                                Text("✓ REAL ANSWER")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.green)
                            } else if item.seat >= 0 {
                                Text("by P\(item.seat + 1)")
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if fooledCount > 0 {
                            Text("🎭 ×\(fooledCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isReal ? .green : .orange)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background((isReal ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(isReal ? Color.green.opacity(0.1) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isReal ? Color.green.opacity(0.45) : Color.white.opacity(0.06), lineWidth: isReal ? 1.5 : 0.75))
                }
            }
            .padding(.horizontal, 16)

            Button {
                session.submit(.bluff(.advance))
            } label: {
                Label("Next Word", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableTileStyle())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)

            scoreRow(g)
        }
    }

    // MARK: - Result screen

    private func resultScreen(_ g: BluffGame) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("🎭 Bluff! Complete")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                let rank = g.ranking()
                ForEach(0..<rank.count, id: \.self) { r in
                    let medal = ["🥇","🥈","🥉",""][min(r, 3)]
                    HStack(spacing: 12) {
                        Text(medal).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                ForEach(rank[r], id: \.self) { seat in
                                    Text(session.playerName(seat: seat))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(session.localHumanSeats.contains(seat) ? .purple : .white)
                                }
                            }
                            Text("\(g.scores[rank[r][0]]) pts")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.white.opacity(r == 0 ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(r == 0 ? .purple.opacity(0.45) : .white.opacity(0.08), lineWidth: 1.5))
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Helpers

    private func wordCard(_ word: BluffWord, phase: BluffGame.Phase) -> some View {
        let accent: Color = phase == .defining ? .purple : (phase == .revealing ? .green : .indigo)
        return VStack(spacing: 8) {
            Text(word.word)
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(.white)
            if !word.category.isEmpty {
                Text(word.category.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(2)
                    .foregroundStyle(accent.opacity(0.8))
            }
            if phase == .revealing {
                Divider().background(.white.opacity(0.2)).padding(.horizontal, 12)
                Text("Real: \"\(word.realDefinition)\"")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .italic()
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(accent.opacity(0.15))
                RoundedRectangle(cornerRadius: 22).strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
            }
        )
        .shadow(color: accent.opacity(0.25), radius: 14, x: 0, y: 4)
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private func waitingCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func scoreRow(_ g: BluffGame) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<g.numPlayers, id: \.self) { seat in
                    let isActive = seat == g.currentActor
                    VStack(spacing: 2) {
                        Text(session.playerName(seat: seat))
                            .font(.system(size: 9, weight: .bold)).lineLimit(1)
                            .foregroundStyle(session.localHumanSeats.contains(seat) ? .purple : .white.opacity(0.6))
                        Text("\(g.scores[seat])")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(isActive ? .purple : .white)
                            .contentTransition(.numericText())
                    }
                    .frame(minWidth: 48).padding(.vertical, 7)
                    .background(isActive ? Color.purple.opacity(0.15) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isActive ? Color.purple.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }
}
