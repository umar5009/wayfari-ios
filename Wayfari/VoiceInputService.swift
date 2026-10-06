import Foundation
import Speech
import AVFoundation
import Combine

/// Push-to-talk speech recognition for tour planning queries.
@MainActor
final class VoiceInputService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var partialTranscript = ""
    @Published var errorMessage: String?
    @Published var authorizationDenied = false

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speech else {
            authorizationDenied = true
            errorMessage = "Microphone & speech access is needed for voice planning. Enable it in Settings."
            return false
        }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        guard micGranted else {
            authorizationDenied = true
            errorMessage = "Microphone access is required. Enable it in Settings → Wayfari."
            return false
        }
        authorizationDenied = false
        return true
    }

    func toggle() {
        if isListening {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        guard await requestPermissions() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available on this device right now."
            return
        }

        stopEngineOnly()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn’t start the microphone: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        recognitionRequest = request
        audioEngine = engine
        partialTranscript = ""
        transcript = ""
        isListening = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Audio engine failed: \(error.localizedDescription)"
            stop()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.transcript = result.bestTranscription.formattedString
                        self.stop()
                    }
                }
                if let error, (error as NSError).code != 216 { // 216 = cancelled
                    // Ignore cancellation; surface real errors
                    if self.isListening {
                        self.errorMessage = error.localizedDescription
                        self.stop()
                    }
                }
            }
        }
    }

    /// Stops listening and finalises the current partial text as the transcript.
    func stop() {
        if !partialTranscript.isEmpty {
            transcript = partialTranscript
        }
        stopEngineOnly()
        isListening = false
    }

    private func stopEngineOnly() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clearTranscript() {
        transcript = ""
        partialTranscript = ""
    }
}
