import SwiftUI

/// Pause control shared by the tick-driven games (Blocks, Capsules,
/// Muncher, Hopper, Nibbles). The owning view's clock loop checks the
/// binding; the overlay dims the board and offers resume.
struct ArcadePauseButton: View {
    @Binding var paused: Bool

    var body: some View {
        Button {
            paused.toggle()
            SoundFX.shared.play(.click)
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}

struct PausedCurtain: View {
    @Binding var paused: Bool

    var body: some View {
        if paused {
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 44))
                    Text("Paused")
                        .font(.headline)
                    Button("Resume") {
                        paused = false
                        SoundFX.shared.play(.click)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
        }
    }
}
