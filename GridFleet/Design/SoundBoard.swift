import AVFoundation

/// Game sounds, synthesized at launch so the app ships no audio files.
/// Plays alongside the player's music and respects the silent switch.
@MainActor
final class SoundBoard {
    enum Sound: String, CaseIterable, Identifiable {
        case whistle, splash, explosion, sunk, sonar, torpedo, radio, aim, tap, fanfare, lament, periscope, peg
        var id: String { rawValue }
    }

    static let shared = SoundBoard()

    var enabled = true

    /// A per-sound level on top of the volume each call asks for, tuned in the sound lab.
    private(set) var gains: [Sound: Float] = [:]

    func gain(for sound: Sound) -> Float { gains[sound] ?? 1 }

    func setGain(_ gain: Float, for sound: Sound) {
        gains[sound] = gain
        UserDefaults.standard.set(gain, forKey: "soundGain.\(sound.rawValue)")
    }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var prepared = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        for sound in Sound.allCases {
            if let gain = UserDefaults.standard.object(forKey: "soundGain.\(sound.rawValue)") as? Double {
                gains[sound] = Float(gain)
            }
        }
    }

    /// Builds the sounds and starts the audio engine. Cheap to call more than once.
    func prepare() {
        guard !prepared else { return }
        prepared = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sound in Sound.allCases { buffers[sound] = synthesize(sound) }
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        for _ in 0..<10 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: mixer, format: format)
            voices.append(voice)
        }
        mixer.outputVolume = 0.8
        try? engine.start()
    }

    func play(_ sound: Sound, volume: Float = 1, pan: Float = 0) {
        guard enabled else { return }
        prepare()
        guard let buffer = buffers[sound] else { return }
        if !engine.isRunning { try? engine.start() }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = min(1, volume * gain(for: sound))
        voice.pan = pan
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.play()
    }

    // MARK: Synthesis

    private func synthesize(_ sound: Sound) -> AVAudioPCMBuffer {
        let rate = 44_100.0
        let duration: Double = switch sound {
        case .whistle: 0.42
        case .splash: 0.7
        case .explosion: 1.0
        case .sunk: 1.8
        case .sonar: 1.5
        case .torpedo: 0.9
        case .radio: 0.28
        case .aim: 0.07
        case .tap: 0.03
        case .fanfare: 1.4
        case .lament: 1.6
        case .periscope: 0.8
        case .peg: 0.09
        }
        let count = Int(duration * rate)
        var samples = [Float](repeating: 0, count: count)
        var noise = NoiseSource()
        var lowpass: Float = 0
        var phase = 0.0
        var phase2 = 0.0

        for i in 0..<count {
            let t = Double(i) / rate
            let p = t / duration
            var s = 0.0
            switch sound {
            case .whistle:
                // Falling pitch, as a shell drops toward you.
                let f = 1900 * pow(0.32, p)
                phase += 2 * .pi * (f + 25 * sin(t * 40)) / rate
                s = sin(phase) * 0.22 * envelope(p, attack: 0.15, release: 0.2)

            case .splash:
                let cutoff = Float(0.5 * pow(0.08, p))
                lowpass += cutoff * (Float(noise.next()) - lowpass)
                s = Double(lowpass) * 1.6 * exp(-5 * t) * envelope(p, attack: 0.01, release: 0.3)
                // Droplets.
                for (start, freq) in [(0.12, 2600.0), (0.2, 3100.0), (0.31, 2300.0)] where t > start && t < start + 0.04 {
                    s += sin(2 * .pi * freq * (t - start) * (1 + (t - start) * 8)) * 0.12 * (1 - (t - start) / 0.04)
                }

            case .explosion, .sunk:
                let long = sound == .sunk
                let cutoff = Float(0.35 * pow(0.06, p))
                lowpass += cutoff * (Float(noise.next()) - lowpass)
                let body = Double(lowpass) * 2.4 * exp(-(long ? 2.2 : 4.0) * t)
                let thump = sin(2 * .pi * 52 * t * (1 - 0.3 * p)) * exp(-7 * t) * 0.9
                let crack = t < 0.012 ? noise.next() * 0.6 : 0
                s = body + thump + crack
                if long {
                    // Groaning hull: a slow detuned saw sliding down.
                    let f = 140 - 70 * p
                    phase += f / rate
                    phase2 += (f * 1.013) / rate
                    let saw = (phase.truncatingRemainder(dividingBy: 1) - 0.5) + (phase2.truncatingRemainder(dividingBy: 1) - 0.5)
                    s += saw * 0.18 * envelope(p, attack: 0.25, release: 0.4) * (0.6 + 0.4 * sin(t * 13))
                }

            case .sonar:
                for (delay, gain) in [(0.0, 0.45), (0.45, 0.18), (0.9, 0.07)] where t >= delay {
                    let local = t - delay
                    s += sin(2 * .pi * 1150 * local) * gain * exp(-9 * local)
                }

            case .torpedo:
                let cutoff: Float = 0.12
                lowpass += cutoff * (Float(noise.next()) - lowpass)
                let bubbles = 0.5 + 0.5 * sin(2 * .pi * 17 * t)
                s = Double(lowpass) * 1.4 * bubbles * envelope(p, attack: 0.2, release: 0.35)

            case .radio:
                // Squelch, then two beeps.
                if t < 0.08 { s = noise.next() * 0.12 * (1 - t / 0.08) }
                for start in [0.1, 0.18] where t > start && t < start + 0.05 {
                    s += sin(2 * .pi * 1450 * t) * 0.16
                }

            case .aim:
                let f = 880 + 520 * p
                phase += 2 * .pi * f / rate
                s = sin(phase) * 0.12 * envelope(p, attack: 0.1, release: 0.6)

            case .tap:
                s = sin(2 * .pi * 2100 * t) * 0.14 * exp(-160 * t)

            case .fanfare:
                // C E G, then a held C chord.
                let notes: [(Double, [Double])] = [(0, [523.25]), (0.14, [659.25]), (0.28, [783.99]), (0.42, [523.25, 659.25, 783.99, 1046.5])]
                for (start, freqs) in notes where t >= start {
                    let local = t - start
                    let held = start >= 0.42
                    let gain = held ? 0.09 * exp(-1.6 * local) : 0.16 * exp(-9 * local)
                    for f in freqs { s += triangle(f * local) * gain }
                }

            case .lament:
                let notes: [(Double, Double)] = [(0, 392.0), (0.4, 311.13), (0.8, 261.63)]
                for (start, f) in notes where t >= start {
                    let local = t - start
                    s += triangle(f * local) * 0.13 * exp(-2.6 * local)
                }

            case .peg:
                // A plastic peg seating in its hole: a click with a little body.
                let cutoff: Float = 0.55
                lowpass += cutoff * (Float(noise.next()) - lowpass)
                s = Double(lowpass) * 0.5 * exp(-110 * t)
                s += sin(2 * .pi * 1750 * t) * 0.22 * exp(-80 * t)
                s += sin(2 * .pi * 420 * t) * 0.25 * exp(-45 * t)

            case .periscope:
                let f = 180 + 260 * p
                phase += f / rate
                let saw = phase.truncatingRemainder(dividingBy: 1) - 0.5
                s = saw * 0.08 * envelope(p, attack: 0.2, release: 0.15)
                if p > 0.93 { s += sin(2 * .pi * 2400 * t) * 0.2 * (1 - (p - 0.93) / 0.07) }
            }
            samples[i] = Float(max(-1, min(1, s)))
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: count)
        }
        return buffer
    }

    private func envelope(_ p: Double, attack: Double, release: Double) -> Double {
        if p < attack { return p / attack }
        if p > 1 - release { return max(0, (1 - p) / release) }
        return 1
    }

    private func triangle(_ cycles: Double) -> Double {
        let x = cycles.truncatingRemainder(dividingBy: 1)
        return 4 * abs(x - 0.5) - 1
    }
}

/// Cheap white noise.
private struct NoiseSource {
    private var state: UInt32 = 0x1234_5678

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
}
