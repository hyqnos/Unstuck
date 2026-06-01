import Foundation
import Observation
@preconcurrency import Speech
@preconcurrency import AVFoundation

enum VoiceCaptureState: Equatable {
    case idle
    case listening
    case processing(String)
    case done(String)
    case error(String)
}

@Observable
@MainActor
final class VoiceCapture {
    var state: VoiceCaptureState = .idle
    var liveText: String = ""

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    // Audio-session + engine setup blocks for seconds — keep it off the main thread
    private let audioQueue = DispatchQueue(label: "unstuck.voice", qos: .userInitiated)

    // MARK: - Public

    func start() {
        Task {
            guard await requestPermissions() else {
                state = .error("Microphone or speech access denied.")
                return
            }
            startListening()
        }
    }

    func stop() {
        finishListening()
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        // Microphone
        let micGranted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micGranted else { return false }

        // Speech
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        return speechStatus == .authorized
    }

    // MARK: - Listening

    private func startListening() {
        guard recognizer != nil else {
            state = .error("Speech recognition not available for this language.")
            return
        }
        stopAudio()
        liveText = ""
        state = .listening

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        // Capture into a local so the background closure never touches main-actor state
        let engine = audioEngine

        // Heavy audio-HAL work OFF the main thread (this was the hang).
        // The outer closure captures only locals; self is touched solely via the
        // MainActor hop with a weak capture — Swift 6 concurrency-clean.
        audioQueue.async {
            let ok: Bool
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement,
                                        options: [.duckOthers, .defaultToSpeaker])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let node = engine.inputNode
                let format = node.outputFormat(forBus: 0)
                node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                }
                engine.prepare()
                try engine.start()
                ok = true
            } catch {
                ok = false
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if ok { self.beginRecognition(request: request) }
                else  { self.state = .error("Audio engine failed.") }
            }
        }
    }

    private func beginRecognition(request: SFSpeechAudioBufferRecognitionRequest) {
        guard case .listening = state else { return }   // cancelled before audio came up
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    self.state = .processing(self.liveText)
                    self.resetSilenceTimer()
                }
                if error != nil || result?.isFinal == true {
                    self.finishListening()
                }
            }
        }
    }

    // MARK: - Silence detection — auto-stop after 2s of no new words

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.finishListening()
            }
        }
    }

    private func finishListening() {
        silenceTimer?.invalidate()
        stopAudio()

        let final = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        state = final.isEmpty ? .idle : .done(final)
    }

    private func stopAudio() {
        recognitionTask?.cancel()
        recognitionTask = nil

        // Hand the blocking teardown to the background queue; swap in a fresh engine on main
        let engine = audioEngine
        let request = recognitionRequest
        recognitionRequest = nil
        audioEngine = AVAudioEngine()

        audioQueue.async {
            request?.endAudio()
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func reset() {
        stopAudio()
        liveText = ""
        state = .idle
    }
}
