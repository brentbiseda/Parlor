import SwiftUI

struct QuiplashView: View {
    @ObservedObject var session: GameSession
    @State private var draftText = ""
    @State private var showAnswer = false
    @FocusState private var textFieldFocused: Bool

    var game: QuiplashGame? { session.game?.engine as? QuiplashGame }

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

    private func gameScreen(_ g: QuiplashGame) -> some View {
        VStack(spacing: 0) {
            progressHeader(g)
            switch g.phase {
            case .writing:  writingPhase(g)
            case .voting:   votingPhase(g)
            case .revealing: revealPhase(g)
            case .over:     EmptyView()
            }
        }
        .onChange(of: g.currentPromptIdx) { _, _ in draftText = ""; showAnswer = false }
        .onChange(of: g.phase) { _, p in
            if p == .writing { draftText = ""; showAnswer = false }
        }
    }

    // MARK: - Progress header

    private func progressHeader(_ g: QuiplashGame) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Prompt \(g.currentPromptIdx + 1) of \(QuiplashGame.promptsPerGame)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                phaseChip(g.phase)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(g.currentPromptIdx) / CGFloat(QuiplashGame.promptsPerGame), height: 5)
                        .animation(.easeInOut(duration: 0.4), value: g.currentPromptIdx)
                }
            }.frame(height: 5)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private func phaseChip(_ phase: QuiplashGame.Phase) -> some View {
        let (label, color): (String, Color) = {
            switch phase {
            case .writing:   return ("✏️ Write", .orange)
            case .voting:    return ("🗳️ Vote", .blue)
            case .revealing: return ("🎉 Results", .green)
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

    // MARK: - Writing phase

    private func writingPhase(_ g: QuiplashGame) -> some View {
        let isMyTurn = session.actionableSeat == g.currentActor || session.localHumanSeats.contains(g.currentActor)
        return VStack(spacing: 16) {
            if let prompt = g.currentPrompt {
                promptCard(prompt.text, accent: .orange)
            }
            Spacer(minLength: 8)

            if isMyTurn {
                VStack(spacing: 10) {
                    Text("P\(g.currentActor + 1) — write your funniest answer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    TextField("Type something funny…", text: $draftText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.5), lineWidth: 1.5))
                        .focused($textFieldFocused)
                        .onAppear { textFieldFocused = true }
                    Button {
                        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        session.submit(.quiplash(.answer(text)))
                        draftText = ""
                        textFieldFocused = false
                    } label: {
                        Label("Submit Answer", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? AnyShapeStyle(.white.opacity(0.1))
                                    : AnyShapeStyle(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)),
                                in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressableTileStyle())
                    .foregroundStyle(.white)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
            } else {
                waitingCard("Waiting for P\(g.currentActor + 1) to write their answer…")
            }
            Spacer(minLength: 4)
            scoreRow(g)
        }
    }

    // MARK: - Voting phase

    private func votingPhase(_ g: QuiplashGame) -> some View {
        let isMyTurn = session.localHumanSeats.contains(g.currentActor)
        let answers = g.currentAnswers
        return VStack(spacing: 12) {
            if let prompt = g.currentPrompt {
                promptCard(prompt.text, accent: .blue)
            }
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Text(isMyTurn ? "PICK THE FUNNIEST ANSWER" : "P\(g.currentActor + 1) IS VOTING…")
                    .font(.system(size: 10, weight: .black)).kerning(2)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(0..<answers.count, id: \.self) { seat in
                    if g.votableSeats.contains(seat) || !isMyTurn {
                        answerButton(
                            text: answers[seat].isEmpty ? "…" : answers[seat],
                            seat: seat,
                            enabled: isMyTurn && g.votableSeats.contains(seat),
                            accent: .blue
                        ) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            session.submit(.quiplash(.vote(seat)))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 4)
            scoreRow(g)
        }
    }

    // MARK: - Reveal phase

    private func revealPhase(_ g: QuiplashGame) -> some View {
        let answers = g.currentAnswers
        let tally   = g.currentVoteTally
        return VStack(spacing: 12) {
            if let prompt = g.currentPrompt {
                promptCard(prompt.text, accent: .green)
            }
            Spacer(minLength: 4)
            VStack(spacing: 8) {
                Text("RESULTS")
                    .font(.system(size: 10, weight: .black)).kerning(2)
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(0..<answers.count, id: \.self) { seat in
                    HStack(spacing: 10) {
                        Text("P\(seat + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28)
                        Text(answers[seat].isEmpty ? "(no answer)" : answers[seat])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let votes = tally[seat] ?? 0
                        if votes > 0 {
                            HStack(spacing: 3) {
                                Text("×\(votes)")
                                    .font(.system(size: 12, weight: .bold))
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.yellow.opacity(0.18), in: Capsule())
                        }
                    }
                    .padding(10)
                    .background((tally[seat] ?? 0) > 0 ? Color.green.opacity(0.12) : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                        (tally[seat] ?? 0) > 0 ? Color.green.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)

            Button {
                session.submit(.quiplash(.advance))
            } label: {
                Label("Next Prompt", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableTileStyle())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .disabled(session.actionableSeat == nil && session.role != .local)

            scoreRow(g)
        }
    }

    // MARK: - Result screen

    private func resultScreen(_ g: QuiplashGame) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("🎉 Prompt Party Over!")
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
                                        .foregroundStyle(session.localHumanSeats.contains(seat) ? .orange : .white)
                                }
                            }
                            Text("\(g.scores[rank[r][0]]) pts")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.white.opacity(r == 0 ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(r == 0 ? .yellow.opacity(0.45) : .white.opacity(0.08), lineWidth: 1.5))
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Helpers

    private func promptCard(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 22).padding(.vertical, 20)
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

    private func answerButton(text: String, seat: Int, enabled: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("P\(seat + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28)
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 1 : 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(enabled ? accent.opacity(0.12) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled ? accent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: enabled ? 1.5 : 0.75))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func scoreRow(_ g: QuiplashGame) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<g.numPlayers, id: \.self) { seat in
                    let isActive = seat == g.currentActor
                    VStack(spacing: 2) {
                        Text(session.playerName(seat: seat))
                            .font(.system(size: 9, weight: .bold)).lineLimit(1)
                            .foregroundStyle(session.localHumanSeats.contains(seat) ? .orange : .white.opacity(0.6))
                        Text("\(g.scores[seat])")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(isActive ? .orange : .white)
                            .contentTransition(.numericText())
                    }
                    .frame(minWidth: 48).padding(.vertical, 7)
                    .background(isActive ? Color.orange.opacity(0.15) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isActive ? Color.orange.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }
}
