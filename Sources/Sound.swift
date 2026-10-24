import AVFoundation

enum SFX: CaseIterable { case bark, yip, crunch, squeak, pop, boing, chime, whine, splash, whoosh }

/// Tiny synthesizer: every sound is generated at launch, so there are no audio files.
final class Sound {
    var muted = false
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [SFX: [AVAudioPCMBuffer]] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var running = false

    init() {
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.45
        do {
            try engine.start()
            players.forEach { $0.play() }
            running = true
        } catch {
            running = false
        }
        build()
    }

    func play(_ s: SFX, volume: Float = 1) {
        guard running, !muted, let variants = buffers[s], let buf = variants.randomElement() else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        p.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    // MARK: - Synthesis

    private func make(_ duration: Double, _ fn: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let n = AVAudioFrameCount(duration * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let out = buf.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            out[i] = Float(max(-1, min(1, fn(t, duration))))
        }
        return buf
    }

    private func noise() -> Double { Double.random(in: -1...1) }

    private func build() {
        buffers[.bark] = [430.0, 380, 470].map { f0 in bark(f0, 0.2) }
        buffers[.yip] = [720.0, 800].map { f0 in bark(f0, 0.11) }

        buffers[.crunch] = (0..<3).map { _ in
            var lp = 0.0
            return make(0.09) { t, _ in
                lp += (self.noise() - lp) * 0.35
                return lp * exp(-t * 45) * 0.9
            }
        }

        buffers[.squeak] = [make(0.17) { t, d in
            let f = 1300 + 700 * sin(.pi * t / d)
            return sin(2 * .pi * f * t + 3 * sin(2 * .pi * 30 * t)) * self.env(t, d, 0.01, 18) * 0.5
        }]

        buffers[.pop] = [make(0.08) { t, d in
            let f = 600 + 900 * (t / d)
            return sin(2 * .pi * f * t) * exp(-t * 50) * 0.6
        }]

        buffers[.boing] = [make(0.22) { t, _ in
            let f = 320 - 180 * min(1, t / 0.22)
            return sin(2 * .pi * f * t + 2 * sin(2 * .pi * 14 * t)) * exp(-t * 14) * 0.6
        }]

        buffers[.chime] = [make(0.7) { t, _ in
            let notes: [(Double, Double)] = [(0, 880), (0.12, 1108.7), (0.24, 1318.5), (0.36, 1760)]
            var v = 0.0
            for (start, f) in notes where t >= start {
                let lt = t - start
                v += sin(2 * .pi * f * lt) * exp(-lt * 7) * 0.22
            }
            return v
        }]

        buffers[.whine] = [make(0.45) { t, d in
            let f = 950 - 250 * (t / d) + 30 * sin(2 * .pi * 9 * t)
            return sin(2 * .pi * f * t) * self.env(t, d, 0.04, 3) * 0.3
        }]

        buffers[.splash] = [{
            var lp = 0.0
            return make(0.45) { t, _ in
                lp += (self.noise() - lp) * 0.2
                let bubbles = 0.6 + 0.4 * sin(2 * .pi * 23 * t)
                return lp * exp(-t * 7) * bubbles * 0.9
            }
        }()]

        buffers[.whoosh] = [{
            var lp = 0.0
            return make(0.25) { t, d in
                let k = 0.05 + 0.25 * sin(.pi * t / d)
                lp += (self.noise() - lp) * k
                return lp * sin(.pi * t / d) * 0.7
            }
        }()]
    }

    private func env(_ t: Double, _ d: Double, _ attack: Double, _ decay: Double) -> Double {
        let a = min(1, t / attack)
        return a * exp(-max(0, t - attack) * decay)
    }

    /// A "woof": a falling, slightly growly harmonic tone with a breathy noise layer.
    private func bark(_ f0: Double, _ dur: Double) -> AVAudioPCMBuffer {
        var phase = 0.0
        var lp = 0.0
        let sr = format.sampleRate
        return make(dur) { t, d in
            let u = t / d
            let f = f0 * (1.0 + 0.45 * sin(.pi * min(1, u * 1.6))) * (1 - 0.3 * u)
            phase += 2 * .pi * f / sr
            lp += (self.noise() - lp) * 0.25
            let tone = 0.55 * sin(phase) + 0.3 * sin(2 * phase) + 0.18 * sin(3 * phase) + 0.08 * sin(5 * phase)
            let growl = 0.8 + 0.2 * sin(2 * .pi * 65 * t)
            let e = min(1, t / 0.012) * exp(-t * 9) * (1 - u * 0.6)
            return (tone * growl + lp * 0.35) * e * 0.8
        }
    }
}
