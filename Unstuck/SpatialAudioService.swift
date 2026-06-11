import AVFoundation
import Foundation

// nonisolated so its Hashable conformance is usable on the background audio queue
nonisolated enum Blip: Hashable { case land, open, complete, dismiss, kick }

/// Each cluster emits a subtle sine tone from its 3D position.
/// Tilting the phone shifts the soundscape — the map sounds like a real space.
final class SpatialAudioService {
    static let shared = SpatialAudioService()
    private init() {}

    private let engine      = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var sources: [AVAudioSourceNode] = []
    private var isRunning = false

    // Spatialized one-shot feedback blips
    private var blipPlayers: [AVAudioPlayerNode] = []
    private var blipBuffers: [Blip: AVAudioPCMBuffer] = [:]
    private var nextBlip = 0

    // Mood-reactive focus music — a slow pulsing pad chord, character set by mood.
    // Plain class: written from the audio queue, read from the render thread; the
    // only shared data are a few doubles, so any torn read is musically harmless.
    final class MusicParams {
        var chord: [Double] = [196.0, 246.9, 293.7]   // G-ish triad
        var pulseHz: Double = 1.0
        var gainTarget: Float = 0                      // 0 = off
        var gain: Float = 0                            // lerped toward target in render
    }
    private let music = MusicParams()
    private var padNode: AVAudioSourceNode?

    // All engine work happens here — NEVER on main (audio HAL calls block for seconds)
    private let audioQueue = DispatchQueue(label: "unstuck.spatialaudio", qos: .utility)

    // Plain snapshot of a cluster — safe to read off the main thread (SwiftData isn't)
    private struct SourceSpec { let freq: Double; let x: Float; let z: Float }

    // Subtle frequency per zone — inspired by Solfeggio scale
    // Low enough to be felt more than consciously heard
    private static let zoneFreq: [ZoneType: Double] = [
        .reminders:      174,
        .health:         285,
        .timeManagement: 396,
        .routines:       417,
        .ideas:          528,
        .captures:       639,
        .someday:        741,
    ]

    // MARK: - Setup

    /// Called on the main thread. Snapshots cluster positions, then does ALL
    /// audio setup on a background queue so the main thread never blocks.
    @MainActor
    func start(clusters: [Cluster]) {
        guard !isRunning, !clusters.isEmpty else { return }
        guard !AppSettings.shared.calmMode else { return }   // calm mode → silence
        isRunning = true   // set early to prevent a double-start race

        // Snapshot on main (SwiftData models are main-only) into plain values
        let specs: [SourceSpec] = clusters.map { c in
            SourceSpec(
                freq: Self.zoneFreq[c.zoneType] ?? 432,
                x: Float(c.positionX - 0.5) * 4,
                z: Float(c.positionY - 0.5) * 4
            )
        }

        audioQueue.async { [weak self] in
            self?.setup(specs)
        }
    }

    private func setup(_ specs: [SourceSpec]) {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .ambient, mode: .default, options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { isRunning = false; return }

        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode,
                       format: engine.mainMixerNode.outputFormat(forBus: 0))

        environment.reverbBlend        = 0.2
        environment.renderingAlgorithm = .sphericalHead
        environment.listenerPosition   = AVAudio3DPoint(x: 0, y: 0, z: 0)
        engine.mainMixerNode.outputVolume = 0.0

        for spec in specs { addSource(spec) }
        setupBlips()
        setupMusicPad()

        do {
            try engine.start()
            // Raise master so blips are audible; ambient drones stay tiny internally
            audioQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.engine.mainMixerNode.outputVolume = 0.5
            }
        } catch {
            isRunning = false
        }
    }

    // MARK: - Mood-reactive focus music

    private func setupMusicPad() {
        let sr = 22050.0
        let table = Self.sineTable
        let N = Self.tableSize
        let music = self.music             // capture the params, not self
        var phases = [0.0, 0.0, 0.0]
        var globalT = 0.0

        let node = AVAudioSourceNode { _, _, frameCount, abl in
            let abl = UnsafeMutableAudioBufferListPointer(abl)
            let chord = music.chord
            let pulseHz = music.pulseHz
            let target = music.gainTarget
            return table.withUnsafeBufferPointer { tbl -> OSStatus in
                for frame in 0..<Int(frameCount) {
                    // Smoothly ramp gain toward target — no clicks on mood/enable change
                    music.gain += (target - music.gain) * 0.0004
                    let pulse = Float(0.55 + 0.45 * sin(2.0 * Double.pi * pulseHz * globalT))
                    var s: Float = 0
                    let count = Swift.min(chord.count, phases.count)
                    for i in 0..<count {
                        let inc = Double(N) * chord[i] / sr
                        phases[i] += inc
                        if phases[i] >= Double(N) { phases[i] -= Double(N) }
                        s += tbl[Int(phases[i]) & (N - 1)]
                    }
                    s = (count > 0 ? s / Float(count) : 0) * music.gain * pulse
                    globalT += 1.0 / sr
                    for buffer in abl {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                    }
                }
                return noErr
            }
        }
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: monoFormat)   // centered bed
        padNode = node
    }

    /// Turn the focus-music bed on/off (smooth, no clicks).
    func setMusicEnabled(_ on: Bool, mode: BrainMode) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.applyMood(mode, enabled: on)
        }
    }

    /// Update the music's character to match the current brain mode.
    func setMood(_ mode: BrainMode) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let enabled = self.music.gainTarget > 0
            self.applyMood(mode, enabled: enabled)
        }
    }

    private func applyMood(_ mode: BrainMode, enabled: Bool) {
        // chord, pulse tempo, and bed level per mood
        switch mode {
        case .ready:                                   // bright, gentle mid pulse
            music.chord = [196.0, 246.9, 293.7]
            music.pulseHz = 0.9
            music.gainTarget = enabled ? 0.10 : 0
        case .hyperfocus:                              // deep, slow, locked-in
            music.chord = [110.0, 164.8, 220.0]
            music.pulseHz = 0.45
            music.gainTarget = enabled ? 0.09 : 0
        case .lowBattery:                              // warm, very slow pad
            music.chord = [174.6, 220.0, 261.6]
            music.pulseHz = 0.35
            music.gainTarget = enabled ? 0.07 : 0
        case .overwhelm:                               // sparse, calming, two tones
            music.chord = [130.8, 196.0]
            music.pulseHz = 0.25
            music.gainTarget = enabled ? 0.05 : 0
        }
    }

    // MARK: - Feedback blips

    private func setupBlips() {
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else { return }

        // Pre-render short enveloped tones (sin() here is fine — once, not in a loop)
        blipBuffers[.land]     = makeBlip(frequency: 440, duration: 0.16)
        blipBuffers[.open]     = makeBlip(frequency: 330, duration: 0.14)
        blipBuffers[.complete] = makeBlip(frequency: 660, duration: 0.22)
        blipBuffers[.dismiss]  = makeBlip(frequency: 520, duration: 0.12)
        blipBuffers[.kick]     = makeKick()   // the laser-show beat

        // Pool of player nodes attached to the 3D environment
        for _ in 0..<5 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: environment, format: monoFormat)
            player.volume = 1.0
            blipPlayers.append(player)
        }
    }

    private func makeBlip(frequency: Double, duration: Double) -> AVAudioPCMBuffer {
        let sr = 22050.0
        let frames = AVAudioFrameCount(sr * duration)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let ptr = buf.floatChannelData?[0] else {
            // Return empty buffer on failure
            return AVAudioPCMBuffer()
        }
        buf.frameLength = frames
        let w = 2.0 * Double.pi * frequency / sr
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let attack = Swift.min(1.0, t / 0.004)        // 4ms attack
            let decay  = exp(-t * 13.0)                    // smooth tail
            ptr[i] = Float(sin(w * Double(i)) * attack * decay * 0.6)
        }
        return buf
    }

    /// A club kick: a sine whose pitch DROPS 150→45 Hz over the hit (that fall is what
    /// reads as "kick drum" rather than "beep"), fast decay, slight saturation.
    private func makeKick() -> AVAudioPCMBuffer {
        let sr = 22050.0, duration = 0.24
        let frames = AVAudioFrameCount(sr * duration)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let ptr = buf.floatChannelData?[0] else { return AVAudioPCMBuffer() }
        buf.frameLength = frames
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let f = 45 + 105 * exp(-t * 28)               // the pitch drop
            phase += 2.0 * .pi * f / sr
            let attack = Swift.min(1.0, t / 0.002)
            let decay  = exp(-t * 16.0)
            let s = sin(phase) * attack * decay
            ptr[i] = Float(tanh(s * 1.8) * 0.85)          // soft clip = punch
        }
        return buf
    }

    /// Play a feedback blip positioned at a cluster's spot on the map (normalized 0…1).
    func playBlip(_ kind: Blip, atX nx: Double, y ny: Double) {
        guard isRunning else { return }
        audioQueue.async { [weak self] in
            guard let self, let buf = self.blipBuffers[kind], !self.blipPlayers.isEmpty else { return }
            let player = self.blipPlayers[self.nextBlip % self.blipPlayers.count]
            self.nextBlip += 1
            player.position = AVAudio3DPoint(x: Float((nx - 0.5) * 4), y: 0, z: Float((ny - 0.5) * 4))
            player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !player.isPlaying { player.play() }
        }
    }

    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.engine.mainMixerNode.outputVolume = 0
            self.engine.stop()
            // Detach everything so a later start() rebuilds cleanly (no node leak / double-attach)
            for s in self.sources      { self.engine.detach(s) }
            for p in self.blipPlayers  { self.engine.detach(p) }
            self.engine.detach(self.environment)
            self.sources.removeAll()
            self.blipPlayers.removeAll()
            self.blipBuffers.removeAll()
            self.isRunning = false
        }
    }

    // MARK: - Listener orientation

    func updateListener(pitch: Double, roll: Double, yaw: Double) {
        guard isRunning else { return }
        audioQueue.async { [weak self] in
            self?.environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw:   Float(-roll  * 60),
                pitch: Float( pitch * 30),
                roll:  0
            )
        }
    }

    // MARK: - Wavetable (precomputed once — no sin() in the audio hot loop)

    private static let tableSize = 2048
    private static let sineTable: [Float] = (0..<tableSize).map {
        Float(sin(2.0 * Double.pi * Double($0) / Double(tableSize)))
    }

    // MARK: - Private

    private func addSource(_ spec: SourceSpec) {
        let freq       = spec.freq
        let sampleRate = 22050.0   // half rate — plenty for sub-500Hz sine tones

        // Integer phase accumulator into the wavetable — classic DSP optimization.
        // Replaces a transcendental sin() per sample with one array read + add.
        let tableSize  = Self.tableSize
        let table      = Self.sineTable
        let phaseInc   = Double(tableSize) * freq / sampleRate   // table steps per sample
        var phaseIndex = 0.0

        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            return table.withUnsafeBufferPointer { tbl -> OSStatus in
                for frame in 0..<Int(frameCount) {
                    let idx = Int(phaseIndex) & (tableSize - 1)   // wrap (tableSize is power of 2)
                    let sample = tbl[idx] * 0.006                 // subtle hum under the blips
                    phaseIndex += phaseInc
                    if phaseIndex >= Double(tableSize) { phaseIndex -= Double(tableSize) }
                    for buffer in abl {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                }
                return noErr
            }
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(source)
        engine.connect(source, to: environment, format: format)

        // Position in 3D — precomputed in the snapshot
        source.position = AVAudio3DPoint(x: spec.x, y: 0, z: spec.z)

        sources.append(source)
    }
}
