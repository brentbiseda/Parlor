import SwiftUI

// MARK: - Main view

struct TriviaView: View {
    @ObservedObject var session: GameSession

    @State private var timeLeft: Double = Double(TriviaGame.timeLimitSeconds)
    @State private var timerRunning = false
    @State private var selectedOption: Int? = nil
    @State private var revealed = false
    @State private var flashCorrect = false
    @State private var questionKey = UUID()   // forces re-entrance animation
    @State private var resultFlash: String? = nil

    var game: TriviaGame? { session.game?.engine as? TriviaGame }

    // Category color map
    func catColor(_ cat: TriviaCategory) -> Color {
        switch cat.tintName {
        case "blue":   return Color(red: 0.28, green: 0.55, blue: 0.98)
        case "brown":  return Color(red: 0.65, green: 0.42, blue: 0.22)
        case "green":  return Color(red: 0.22, green: 0.80, blue: 0.42)
        case "orange": return Color(red: 0.95, green: 0.52, blue: 0.12)
        case "purple": return Color(red: 0.68, green: 0.32, blue: 0.95)
        case "pink":   return Color(red: 0.92, green: 0.35, blue: 0.65)
        case "indigo": return Color(red: 0.38, green: 0.32, blue: 0.92)
        case "teal":   return Color(red: 0.15, green: 0.82, blue: 0.75)
        case "yellow": return Color(red: 0.95, green: 0.80, blue: 0.18)
        case "red":    return Color(red: 0.92, green: 0.22, blue: 0.28)
        default:       return .white
        }
    }

    var body: some View {
        if let g = game {
            if g.isOver {
                resultScreen(g)
            } else {
                gameScreen(g)
                    .onChange(of: g.currentQ) { _, _ in
                        transitionToNextQuestion()
                    }
                    .onChange(of: g.currentSeat) { old, new in
                        // When it becomes this player's turn (seat 0), start timer
                        if new == 0 { startTimer() }
                    }
                    .onAppear { startTimer() }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Game screen

    private func gameScreen(_ g: TriviaGame) -> some View {
        VStack(spacing: 0) {
            progressHeader(g)
            if let q = g.currentQuestion {
                VStack(spacing: 12) {
                    categoryTag(q)
                        .padding(.top, 14)
                    questionCard(q)
                    Spacer(minLength: 8)
                    optionGrid(q, g: g)
                        .padding(.horizontal, 12)
                    Spacer(minLength: 10)
                }
                .id(questionKey)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: questionKey)
            }
            scoreRow(g)
        }
    }

    // MARK: - Header

    private func progressHeader(_ g: TriviaGame) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Q\(g.currentQ + 1) of \(TriviaGame.questionsPerGame)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                // Timer arc
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, timeLeft) / Double(TriviaGame.timeLimitSeconds)))
                        .stroke(timerColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timeLeft)
                    Text("\(Int(ceil(timeLeft)))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(timerColor)
                }
                .frame(width: 36, height: 36)
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Color(red: 0.35,green:0.75,blue:1.0), .cyan],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(g.currentQ) / CGFloat(TriviaGame.questionsPerGame),
                               height: 5)
                        .animation(.easeInOut(duration: 0.4), value: g.currentQ)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Category tag

    private func categoryTag(_ q: TriviaQ) -> some View {
        let col = catColor(q.cat)
        return HStack(spacing: 6) {
            Image(systemName: q.cat.icon)
                .font(.system(size: 12, weight: .bold))
            Text(q.cat.rawValue.uppercased())
                .font(.system(size: 11, weight: .black)).kerning(1.5)
            Text("·")
            Text(q.diff.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(col)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(col.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(col.opacity(0.4), lineWidth: 0.75))
    }

    // MARK: - Question card

    private func questionCard(_ q: TriviaQ) -> some View {
        Text(q.q)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
            )
            .padding(.horizontal, 12)
    }

    // MARK: - Option grid

    private func optionGrid(_ q: TriviaQ, g: TriviaGame) -> some View {
        let actionable = session.actionableSeat != nil && !revealed
        let col = catColor(q.cat)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                         spacing: 10) {
            ForEach(0..<4, id: \.self) { i in
                optionButton(i, option: q.a[i], correct: q.c, enabled: actionable, accent: col, q: q)
            }
        }
    }

    @ViewBuilder
    private func optionButton(_ i: Int, option: String, correct: Int, enabled: Bool, accent: Color, q: TriviaQ) -> some View {
        let isSelected = selectedOption == i
        let isCorrect  = i == correct
        let showResult = revealed

        let bg: Color = {
            if !showResult { return isSelected ? accent.opacity(0.35) : .white.opacity(0.07) }
            if isCorrect   { return Color(red: 0.18, green: 0.82, blue: 0.38).opacity(0.35) }
            if isSelected  { return Color(red: 0.92, green: 0.25, blue: 0.30).opacity(0.35) }
            return .white.opacity(0.04)
        }()
        let border: Color = {
            if !showResult { return isSelected ? accent : .white.opacity(0.12) }
            if isCorrect   { return Color(red: 0.18, green: 0.82, blue: 0.38) }
            if isSelected  { return Color(red: 0.92, green: 0.25, blue: 0.30) }
            return .white.opacity(0.08)
        }()
        let icon: String? = {
            guard showResult else { return nil }
            if isCorrect  { return "checkmark.circle.fill" }
            if isSelected { return "xmark.circle.fill" }
            return nil
        }()

        Button {
            guard enabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedOption = i
            revealed = true
            timerRunning = false
            let isRight = i == q.c
            if isRight {
                SoundFX.shared.play(.jackpot)
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { flashCorrect = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { flashCorrect = false }
                }
            } else {
                SoundFX.shared.play(.error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            session.submit(.trivia(.answer(i)))
            scheduleAutoAdvance()
        } label: {
            HStack(spacing: 8) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isCorrect ? Color(red: 0.18, green: 0.82, blue: 0.38) : Color(red: 0.92, green: 0.25, blue: 0.30))
                }
                Text(option)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(showResult && !isCorrect && !isSelected ? 0.4 : 0.95))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: isSelected || (showResult && isCorrect) ? 2 : 0.75))
            .shadow(color: (showResult && isCorrect) ? Color(red: 0.18, green: 0.82, blue: 0.38).opacity(0.5) : .clear, radius: 10)
            .scaleEffect(isSelected && !showResult ? 0.97 : 1.0)
            .animation(.spring(response: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Score row

    private func scoreRow(_ g: TriviaGame) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<g.numPlayers, id: \.self) { seat in
                let isMe = session.localHumanSeats.contains(seat)
                let isCurrent = seat == g.currentSeat && !g.isOver
                VStack(spacing: 2) {
                    Text(session.playerName(seat: seat))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isMe ? .teal : .white.opacity(0.65))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(g.scores[seat])")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(isCurrent ? .yellow : .white)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrent ? .yellow.opacity(0.12) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isCurrent ? .yellow.opacity(0.5) : .clear, lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Result screen

    private func resultScreen(_ g: TriviaGame) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("🎉 Quiz Complete!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 28)

                // Winner podium
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
                                        .foregroundStyle(session.localHumanSeats.contains(seat) ? .teal : .white)
                                }
                            }
                            let seat0 = rank[r][0]
                            let correctAmt = correctCountFor(g, seat: seat0)
                            Text("\(g.scores[seat0]) pts · \(correctAmt)/\(TriviaGame.questionsPerGame) correct")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.white.opacity(r == 0 ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(r == 0 ? .yellow.opacity(0.45) : .white.opacity(0.08), lineWidth: 1.5))
                    .padding(.horizontal, 12)
                }

                // Question recap
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUESTION RECAP")
                        .font(.system(size: 10, weight: .black)).kerning(2)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.leading, 4)
                    ForEach(0..<TriviaGame.questionsPerGame, id: \.self) { qi in
                        if let q = g.questionAt(qi) {
                            recapRow(g, q: q, qi: qi)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private func recapRow(_ g: TriviaGame, q: TriviaQ, qi: Int) -> some View {
        let humanSeat = 0
        let ans = g.answerFor(seat: humanSeat, question: qi)
        let correct = ans == q.c
        let catCol = catColor(q.cat)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: correct ? "checkmark.circle.fill" : (ans == nil ? "clock.fill" : "xmark.circle.fill"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(correct ? Color(red: 0.22, green: 0.82, blue: 0.42) :
                                 ans == nil ? .yellow : Color(red: 0.92, green: 0.28, blue: 0.32))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: q.cat.icon).font(.caption2).foregroundStyle(catCol)
                    Text(q.cat.rawValue).font(.caption2.weight(.semibold)).foregroundStyle(catCol)
                }
                Text(q.q)
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                Text("✓ \(q.a[q.c])")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.22, green: 0.82, blue: 0.42))
                if let a = ans, a != q.c {
                    Text("✗ \(q.a[a])")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.32))
                }
            }
            Spacer()
            Text("+\(correct ? q.diff.pointValue : 0)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(correct ? .yellow : .white.opacity(0.3))
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.08), lineWidth: 0.75))
    }

    // MARK: - Timer

    private var timerColor: Color {
        if timeLeft > 10 { return Color(red: 0.22, green: 0.82, blue: 0.42) }
        if timeLeft > 5  { return .yellow }
        return Color(red: 0.92, green: 0.28, blue: 0.32)
    }

    private func startTimer() {
        guard let g = game, !g.isOver, g.currentSeat == 0,
              session.actionableSeat != nil else { return }
        timeLeft = Double(TriviaGame.timeLimitSeconds)
        timerRunning = true
        selectedOption = nil
        revealed = false
        runTimer()
    }

    private func runTimer() {
        guard timerRunning else { return }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            guard timerRunning else { t.invalidate(); return }
            guard let g = game, !g.isOver else { t.invalidate(); return }
            timeLeft = max(0, timeLeft - 0.5)
            if timeLeft <= 0 {
                t.invalidate()
                timerRunning = false
                revealed = true
                SoundFX.shared.play(.error)
                session.submit(.trivia(.timeOut))
                scheduleAutoAdvance()
            }
        }
    }

    private func scheduleAutoAdvance() {
        // Auto-advance after a brief reveal, once bots have also answered
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            transitionToNextQuestion()
        }
    }

    private func transitionToNextQuestion() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            questionKey = UUID()
            selectedOption = nil
            revealed = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startTimer()
        }
    }

    private func correctCountFor(_ g: TriviaGame, seat: Int) -> Int {
        (0..<TriviaGame.questionsPerGame).filter { qi in
            guard let ans = g.answerFor(seat: seat, question: qi),
                  let q = g.questionAt(qi) else { return false }
            return ans == q.c
        }.count
    }
}
