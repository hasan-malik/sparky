//
//  VoiceManager.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-30.
//

import Foundation
import Speech
import AVFoundation
import Combine

final class VoiceManager: NSObject, ObservableObject {

    // MARK: - Published UI State
    @Published var statusText: String = "Tap the microphone and talk to Sparky."
    @Published var isListening: Bool = false

    // MARK: - Audio / Speech
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // MARK: - Public API

    /// Call from ContentView.onAppear()
    func requestPermissionsOnly() {
        guard let speechRecognizer else {
            statusText = "Speech recognition isn’t available on this device."
            return
        }

        if !speechRecognizer.isAvailable {
            statusText = "Speech recognition is temporarily unavailable."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.speak("Hi, I’m Sparky. Tap the microphone and talk to me.")
                case .denied:
                    self.statusText = "Speech permission denied. Enable it in Settings."
                case .restricted:
                    self.statusText = "Speech recognition is restricted on this device."
                case .notDetermined:
                    self.statusText = "Speech permission not determined."
                @unknown default:
                    self.statusText = "Speech permission error."
                }
            }
        }
    }

    /// Wire this to your mic button.
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    // MARK: - Listening Lifecycle

    private func startListening() {
        // Ensure speech is authorized before starting
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Please enable Speech Recognition in Settings."
            return
        }

        // Clean slate
        stopListening()

        // Configure audio session (this will also trigger mic permission prompt on first use)
        do {
            try configureAudioSessionForSpeech()
        } catch {
            statusText = "Audio session error: \(error.localizedDescription)"
            return
        }

        // Build recognition request
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        self.request = newRequest

        let inputNode = audioEngine.inputNode

        // ✅ Critical: use inputFormat (simulator-safe)
        let format = inputNode.inputFormat(forBus: 0)

        // Guard against invalid formats (simulator can sometimes be weird)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusText = "Mic input not ready. In Simulator: I/O → Audio Input → Mac Microphone."
            cleanupAfterFailedStart()
            return
        }

        // Install tap
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            statusText = "Audio engine failed: \(error.localizedDescription)"
            cleanupAfterFailedStart()
            return
        }

        isListening = true
        statusText = "Listening…"

        // Start recognition task
        guard let speechRecognizer else {
            statusText = "Speech recognizer not available."
            cleanupAfterFailedStart()
            return
        }

        task = speechRecognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let spokenText = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.statusText = spokenText.isEmpty ? "Listening…" : "Hearing: “\(spokenText)”"
                }

                if result.isFinal {
                    self.handleUserInput(spokenText)
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.statusText = "Speech error: \(error.localizedDescription)"
                    self.stopListening()
                }
            }
        }
    }

    private func stopListening() {
        // Stop recognition task first
        task?.cancel()
        task = nil

        // End request
        request?.endAudio()
        request = nil

        // Stop audio engine + remove tap
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Deactivate audio session (best practice)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        isListening = false
    }

    // MARK: - Conversation Handling

    private func handleUserInput(_ text: String) {
        stopListening()

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusText = "I didn’t catch that. Tap the microphone and try again."
            speak("I didn’t catch that. Tap the microphone and try again.")
            return
        }

        statusText = "You said: “\(cleaned)”"

        // For now: demo responses (we’ll replace with triage state machine / AI tool calls)
        let response = fakeAIResponse(for: cleaned)

        // Small delay so it feels natural
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.speak(response)
        }
    }

    private func fakeAIResponse(for input: String) -> String {
        let lower = input.lowercased()

        if lower.contains("sick") || lower.contains("not feeling well") || lower.contains("feel unwell") {
            return "I’m sorry you’re not feeling well. Are you having chest pain or trouble breathing?"
        }

        if lower.contains("ride") || lower.contains("drive") || lower.contains("transport") {
            return "Okay. I can help with a ride. What day and time do you need to leave?"
        }

        if lower.contains("appointment") || lower.contains("doctor") || lower.contains("clinic") || lower.contains("reschedule") {
            return "I can help with an appointment. Would mornings or afternoons work better?"
        }

        if lower.contains("emergency") || lower.contains("er") {
            return "I can help you decide. Are you having severe chest pain, trouble breathing, or signs of a stroke?"
        }

        return "Thanks. I can help with care questions, appointments, or rides. What would you like to do?"
    }

    // MARK: - Speech Output

    private func speak(_ text: String) {
        statusText = text

        // Stop speaking if already speaking (prevents overlapping)
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5

        speechSynthesizer.speak(utterance)
    }

    // MARK: - Audio Session

    private func configureAudioSessionForSpeech() throws {
        // Spoken-audio optimized settings; defaultToSpeaker is important so voice comes out loud.
        try audioSession.setCategory(.playAndRecord,
                                     mode: .spokenAudio,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private func cleanupAfterFailedStart() {
        // Ensure we’re not left in a half-running state
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        isListening = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
