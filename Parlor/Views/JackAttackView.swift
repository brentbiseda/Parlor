import SwiftUI

struct JackAttackView: View {
    @ObservedObject var session: GameSession
    @State private var timeUsed: Int = 0
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var showScrew = false
    @State private var screwTarget: Int? = nil
    @State private var flashedAnswer: Int? = nil

    var game: JackAttackGame? { session.game?.engine as? JackAttackGame }

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

    private func gameScreen(_ g: JackAttackGame) -> some View {
        VStack(spacing: 0) {
            topBar(g)
            if let q = g.currentQuestion {
                questionCard(q, g)
                Spacer(minLength: 6)
                answerGrid(q, g)
                Spacer(minLength: 6)
                bottomBar(g)
            }
        }
        .task(id: "\(g.currentQ)-\(g.currentSeat)-\(String(describing: g.screwedSeat))") {
            timeUsed = 0
            timerTask?.cancel()
            timerTask = Task {
                while timeUsed < JackAttackGame.timeLimitSeconds {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    timeUsed += 1
                    if timeUsed >= JackAttackGame.timeLimitSeconds {
                        if session.localHumanSeats.contains(g.currentPlayer) {
                            session.submit(.jackAttack(.timeOut))
                        }
                        break
                    }
                }
            }
        }
        .onChange(of: g.isOver) { _, over in if over { timerTask?.cancel() } }
    }

    // MARK: - Top bar

    private func topBar(_ g: JackAttackGame) -> some View {
        HStack(spacing: 12) {
            Text("Q\(g.currentQ + 1)/\(JackAttackGame.questionsPerGame)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            timerArc(g)
            Spacer()
            if let by = g.screwedBy, let target = g.screwedSeat {
                Text("🔩 P\(by + 1)→P\(target + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.red.opacity(0.15), in: Capsule())
            } else {
                Text("P\(g.currentSeat + 1)'s turn")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private func timerArc(_ g: JackAttackGame) -> some View {
        let fraction = Double(timeUsed) / Double(JackAttackGame.timeLimitSeconds)
        let barColor: Color = fraction < 0.6 ? .green : fraction < 0.85 ? .yellow : .red
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 4)
                .frame(width: 38, height: 38)
            Circle()
                .trim(from: 0, to: CGFloat(1 - fraction))
                .stroke(barColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 38, height: 38)
                .animation(.linear(duration: 0.9), value: timeUsed)
            Text("\(JackAttackGame.timeLimitSeconds - timeUsed)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(barColor)
                .contentTransition(.numericText(countsDown: true))
        }
    }

    // MARK: - Question card

    private func questionCard(_ q: JackAttackQuestion, _ g: JackAttackGame) -> some View {
        let isScrewed = g.screwedSeat != nil
        return VStack(spacing: 8) {
            Text(q.category.uppercased())
                .font(.system(size: 9, weight: .black)).kerning(2.5)
                .foregroundStyle(.yellow.opacity(0.7))
            Text(q.q)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(isScrewed ? Color.red.opacity(0.15) : Color.yellow.opacity(0.1))
                RoundedRectangle(cornerRadius: 22).strokeBorder(isScrewed ? Color.red.opacity(0.5) : Color.yellow.opacity(0.4), lineWidth: 1.5)
            }
        )
        .shadow(color: (isScrewed ? Color.red : Color.yellow).opacity(0.2), radius: 14, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Answer grid

    private func answerGrid(_ q: JackAttackQuestion, _ g: JackAttackGame) -> some View {
        let isMyTurn = session.localHumanSeats.contains(g.currentPlayer)
        let colors: [Color] = [.blue, .green, .orange, .pink]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(0..<4, id: \.self) { idx in
                let isFlashed = flashedAnswer == idx
                Button {
                    guard isMyTurn else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    flashedAnswer = idx
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        flashedAnswer = nil
                    }
                    timerTask?.cancel()
                    session.submit(.jackAttack(.answer(idx, timeUsed: timeUsed)))
                } label: {
                    Text(q.a[idx])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 10).padding(.vertical, 12)
                        .background(isFlashed ? colors[idx] : colors[idx].opacity(isMyTurn ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(colors[idx].opacity(isMyTurn ? 0.7 : 0.2), lineWidth: isMyTurn ? 1.5 : 0.75))
                        .scaleEffect(isFlashed ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.12), value: isFlashed)
                }
                .buttonStyle(.plain)
                .disabled(!isMyTurn)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom bar (screw + scores)

    private func bottomBar(_ g: JackAttackGame) -> some View {
        VStack(spacing: 8) {
            if g.screwedSeat == nil && g.screwsLeft[g.currentSeat] > 0 &&
               session.localHumanSeats.contains(g.currentSeat) {
                screwSection(g)
            }
            scoreRow(g)
        }
    }

    private func screwSection(_ g: JackAttackGame) -> some View {
        VStack(spacing: 6) {
            if showScrew {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<g.numPlayers, id: \.self) { seat in
                            if seat != g.currentSeat {
                                Button {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    session.submit(.jackAttack(.screw(seat)))
                                    showScrew = false
                                } label: {
                                    Text("🔩 Screw P\(seat + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(.red.opacity(0.25), in: Capsule())
                                        .overlay(Capsule().strokeBorder(.red.opacity(0.6), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .transition(.asymmetric(insertion: .push(from: .bottom), removal: .push(from: .top)))
            }
            Button {
                withAnimation(.spring(duration: 0.3)) { showScrew.toggle() }
            } label: {
                Label(showScrew ? "Cancel Screw" : "🔩 Use Screw",
                      systemImage: showScrew ? "xmark.circle" : "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(.red.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func scoreRow(_ g: JackAttackGame) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(0..<g.numPlayers, id: \.self) { seat in
                    let isActive = seat == g.currentPlayer
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            Text(session.playerName(seat: seat))
                                .font(.system(size: 9, weight: .bold)).lineLimit(1)
                                .foregroundStyle(session.localHumanSeats.contains(seat) ? .yellow : .white.opacity(0.5))
                            if g.screwsLeft[seat] > 0 {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                        Text("\(g.scores[seat])")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(isActive ? .yellow : .white)
                            .contentTransition(.numericText())
                    }
                    .frame(minWidth: 46).padding(.vertical, 6)
                    .background(isActive ? Color.yellow.opacity(0.15) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isActive ? Color.yellow.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Result screen

    private func resultScreen(_ g: JackAttackGame) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("⚡ Jack Attack!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 10)
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
                                        .foregroundStyle(session.localHumanSeats.contains(seat) ? .yellow : .white)
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
}
