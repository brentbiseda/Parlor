import AVFoundation
import UIKit

/// Sound effects synthesized at runtime — short enveloped tones, chords, and
/// noise bursts rendered into PCM buffers once and played through a small
/// pool of player nodes, so there are no audio assets to ship. Respects the
/// silent switch (.ambient) and a user toggle persisted in UserDefaults.
final class SoundFX {
    static let shared = SoundFX()

    enum Sound {
        // Cards & boards
        case cardPlay, cardDraw, click, tileSelect, tileMatch, undo, error
        // Results
        case win, lose
        // Pinball
        case bumper, sling, target, jackpot, drain, launch, flipper, spinner, tunnel
        // Breakout
        case paddleHit, brick, lifeLost, levelUp
        // Tetris
        case rotate, lock, lineClear
    }

    static let enabledKey = "parlor.sound"

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    private let sampleRate = 44_100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    private init() {}

    private func startIfNeeded() -> Bool {
        guard !started else { return engine.isRunning }
        started = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            for _ in 0..<6 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
            engine.mainMixerNode.outputVolume = 0.6
            try engine.start()
            players.forEach { $0.play() }
            return true
        } catch {
            return false   // no audio (e.g. simulator hiccup) — stay silent
        }
    }

    func play(_ sound: Sound) {
        haptic(for: sound)
        guard enabled, startIfNeeded() else { return }
        guard let buffer = buffer(for: sound) else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    private func haptic(for sound: Sound) {
        switch sound {
        case .bumper, .jackpot, .lineClear, .win:
            mediumImpact.impactOccurred()
        case .drain, .lifeLost, .lock, .target:
            lightImpact.impactOccurred()
        default:
            break
        }
    }

    // MARK: - Synthesis

    private func buffer(for sound: Sound) -> AVAudioPCMBuffer? {
        let key = String(describing: sound)
        if let cached = buffers[key] { return cached }
        let rendered = render(sound)
        buffers[key] = rendered
        return rendered
    }

    private func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        switch sound {
        case .cardPlay: return tone([(1100, 1)], duration: 0.05, decay: 40, volume: 0.5)
        case .cardDraw: return noise(duration: 0.05, lowpass: 0.4, volume: 0.25)
        case .click: return tone([(750, 1)], duration: 0.04, decay: 50, volume: 0.45)
        case .tileSelect: return tone([(950, 1)], duration: 0.05, decay: 45, volume: 0.4)
        case .tileMatch: return tone([(700, 1), (1050, 0.6)], duration: 0.16, decay: 14, volume: 0.5)
        case .undo: return sweep(from: 900, to: 500, duration: 0.12, volume: 0.4)
        case .error: return tone([(220, 1), (233, 0.8)], duration: 0.18, decay: 10, volume: 0.4)
        case .win: return arpeggio([523.25, 659.25, 783.99, 1046.5], step: 0.1, noteDecay: 6, volume: 0.5)
        case .lose: return arpeggio([392, 329.63, 261.63], step: 0.14, noteDecay: 6, volume: 0.45)
        case .bumper: return tone([(320, 1), (640, 0.5)], duration: 0.09, decay: 22, volume: 0.6)
        case .sling: return tone([(500, 1)], duration: 0.06, decay: 30, volume: 0.5)
        case .target: return tone([(880, 1), (1320, 0.4)], duration: 0.1, decay: 18, volume: 0.5)
        case .jackpot: return arpeggio([659.25, 880, 1108.7, 1318.5], step: 0.07, noteDecay: 8, volume: 0.55)
        case .drain: return sweep(from: 400, to: 90, duration: 0.4, volume: 0.5)
        case .launch: return sweep(from: 200, to: 900, duration: 0.25, volume: 0.5)
        case .flipper: return tone([(180, 1)], duration: 0.05, decay: 35, volume: 0.5)
        case .spinner: return tone([(1400, 1)], duration: 0.04, decay: 45, volume: 0.35)
        case .tunnel: return sweep(from: 500, to: 1500, duration: 0.3, volume: 0.45)
        case .paddleHit: return tone([(420, 1)], duration: 0.05, decay: 35, volume: 0.5)
        case .brick: return tone([(950, 0.8), (1250, 0.5)], duration: 0.06, decay: 30, volume: 0.5)
        case .lifeLost: return sweep(from: 600, to: 150, duration: 0.35, volume: 0.5)
        case .levelUp: return arpeggio([523.25, 783.99, 1046.5], step: 0.08, noteDecay: 8, volume: 0.5)
        case .rotate: return tone([(620, 1)], duration: 0.035, decay: 50, volume: 0.4)
        case .lock: return tone([(260, 1), (390, 0.4)], duration: 0.07, decay: 28, volume: 0.55)
        case .lineClear: return arpeggio([587.33, 880, 1174.7], step: 0.06, noteDecay: 9, volume: 0.55)
        }
    }

    private func makeBuffer(duration: Double) -> (AVAudioPCMBuffer, UnsafeMutablePointer<Float>, Int)? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        return (buffer, channel, Int(frames))
    }

    /// Mixed sine partials with an exponential decay envelope.
    private func tone(_ partials: [(freq: Double, amp: Double)], duration: Double,
                      decay: Double, volume: Double) -> AVAudioPCMBuffer? {
        guard let (buffer, channel, frames) = makeBuffer(duration: duration) else { return nil }
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let envelope = exp(-decay * t)
            var sample = 0.0
            for (freq, amp) in partials {
                sample += amp * sin(2 * .pi * freq * t)
            }
            channel[i] = Float(sample * envelope * volume)
        }
        return buffer
    }

    /// Frequency glide (launches, drains, whooshes).
    private func sweep(from start: Double, to end: Double, duration: Double,
                       volume: Double) -> AVAudioPCMBuffer? {
        guard let (buffer, channel, frames) = makeBuffer(duration: duration) else { return nil }
        var phase = 0.0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let freq = start + (end - start) * progress
            phase += 2 * .pi * freq / sampleRate
            let envelope = sin(.pi * progress)   // fade in and out
            channel[i] = Float(sin(phase) * envelope * volume)
        }
        return buffer
    }

    /// A quick run of notes (wins, jackpots, line clears).
    private func arpeggio(_ freqs: [Double], step: Double, noteDecay: Double,
                          volume: Double) -> AVAudioPCMBuffer? {
        let duration = step * Double(freqs.count) + 0.25
        guard let (buffer, channel, frames) = makeBuffer(duration: duration) else { return nil }
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (n, freq) in freqs.enumerated() {
                let onset = Double(n) * step
                guard t >= onset else { continue }
                let local = t - onset
                sample += sin(2 * .pi * freq * local) * exp(-noteDecay * local) * 0.8
            }
            channel[i] = Float(sample * volume)
        }
        return buffer
    }

    /// Filtered noise burst (shuffles, card slides).
    private func noise(duration: Double, lowpass: Double, volume: Double) -> AVAudioPCMBuffer? {
        guard let (buffer, channel, frames) = makeBuffer(duration: duration) else { return nil }
        var last: Double = 0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let white = Double.random(in: -1...1)
            last += lowpass * (white - last)
            channel[i] = Float(last * exp(-20 * t) * volume * 2)
        }
        return buffer
    }
}
