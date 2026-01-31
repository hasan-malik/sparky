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

    enum Role { case user, assistant }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published var statusText: String = "Tap the microphone and talk to Sparky."
    @Published var isListening: Bool = false
    @Published var messages: [ChatMessage] = []

    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // ✅ Keep the latest partial transcript so we can finalize on silence or user stop
    private var lastTranscript: String = ""

    // ✅ 3-second silence auto-finish
    private var silenceWorkItem: DispatchWorkItem?
    private let silenceSeconds: TimeInterval = 3.0
    
    private var didFinalizeThisSession: Bool = false

    private let brain = SparkyBrain(backend: MockBackend())

    // MARK: - Permissions

    func requestPermissionsOnly() {
        guard let speechRecognizer else {
            statusText = "Speech recognition isn’t available on this device."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.append(.assistant, """
                Hi, I’m Sparky!
                
                I'm here to help you with care questions, appointments, or rides. What’s going on?
                """)
                    self.speak("Hi, I’m Sparky! I'm here to help you with care questions, appointments, or rides. What’s going on?")
                    self.statusText = "Ready."
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

    // MARK: - Mic Button

    func toggleListening() {
        if isListening {
            if lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stopListeningSoft()
                statusText = "Stopped. Tap mic to talk."
            } else {
                finalizeCurrentTranscript()
            }
        } else {
            startListening()
        }
    }

    // MARK: - Listening

    private func startListening() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Please enable Speech Recognition in Settings."
            return
        }

        stopListeningHard() // clean slate

        do {
            try configureAudioSessionForSpeech()
        } catch {
            statusText = "Audio session error: \(error.localizedDescription)"
            return
        }

        lastTranscript = ""
        didFinalizeThisSession = false
        cancelSilenceTimer()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        self.request = newRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusText = "Mic input not ready. In Simulator: I/O → Audio Input → Mac Microphone."
            cleanupAfterFailedStart()
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

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

        guard let speechRecognizer else {
            statusText = "Speech recognizer not available."
            cleanupAfterFailedStart()
            return
        }

        task = speechRecognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            if self.didFinalizeThisSession { return }

            if let result = result {
                let spoken = result.bestTranscription.formattedString
                self.lastTranscript = spoken

                DispatchQueue.main.async {
                    self.statusText = spoken.isEmpty ? "Listening…" : "Hearing: “\(spoken)”"
                }

                // ✅ Reset silence timer every time we get an update
                self.scheduleSilenceFinalize()

                if result.isFinal {
                    self.finalizeCurrentTranscript()
                    return
                }
            }

            // If there’s an error, only show it if we weren’t intentionally stopping
            if let error = error as NSError? {
                // Many “errors” are expected when stopping; if we have text, just finalize it.
                if !self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.finalizeCurrentTranscript()
                    return
                }

                DispatchQueue.main.async {
                    self.statusText = "Speech error: \(error.localizedDescription)"
                    self.stopListeningHard()
                }
            }
        }
    }

    /// Finalizes whatever we currently have (used for user tap-to-stop AND silence timeout)
    private func finalizeCurrentTranscript() {
        
        if didFinalizeThisSession { return }
        didFinalizeThisSession = true
        
        cancelSilenceTimer()
        stopListeningSoft()

        let cleaned = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusText = "I didn’t catch that. Tap the mic and try again."
            speak("I didn’t catch that. Tap the mic and try again.")
            return
        }

        append(.user, cleaned)

        let reply = brain.handle(userText: cleaned)
        append(.assistant, reply)
        speak(reply)

        statusText = "Ready. Tap mic to reply."
    }

    /// Soft stop: stop engine/tap and end audio, but don’t aggressively “cancel” in a way that loses transcript.
    private func stopListeningSoft() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        request?.endAudio()
        request = nil

        // Cancelling is fine now because we already captured lastTranscript.
        task?.cancel()
        task = nil

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        isListening = false
    }

    /// Hard stop: used for cleanup paths
    private func stopListeningHard() {
        cancelSilenceTimer()

        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
    }

    // MARK: - Silence Timer

    private func scheduleSilenceFinalize() {
        cancelSilenceTimer()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.didFinalizeThisSession { return }
            if self.isListening {
                self.finalizeCurrentTranscript()
            }
        }
        silenceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceSeconds, execute: item)
    }

    private func cancelSilenceTimer() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
    }

    // MARK: - Speech Output (Warm / Joyful)

    private func speak(_ text: String) {
        statusText = text

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = pickWarmEnglishVoice()

        // Cheerful helper tuning
        utterance.rate = 0.50             // faster, more energetic
        utterance.pitchMultiplier = 1.15   // brighter, friendlier
        utterance.volume = 1.0 // maximum


        speechSynthesizer.speak(utterance)
        
        // ONE-TIME BOY
        for v in AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language.hasPrefix("en") }) {
            print("VOICE:", v.name,
                  "| lang:", v.language,
                  "| quality:", v.quality.rawValue,
                  "| id:", v.identifier)
        }

    }

    private func pickWarmEnglishVoice() -> AVSpeechSynthesisVoice? {

        // Voices that tend to sound cheerful + friendly on iOS
        // (Only used if installed — totally safe)
        let preferredIDs = [
            "com.apple.ttsbundle.Samantha-compact",
            "com.apple.ttsbundle.Ava-compact",
            "com.apple.ttsbundle.allison-compact"
        ]

        for id in preferredIDs {
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                return voice
            }
        }

        // Otherwise: best-quality en-US voice available
        let voices = AVSpeechSynthesisVoice
            .speechVoices()
            .filter { $0.language == "en-US" }

        return voices
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }


    private func append(_ role: Role, _ text: String) {
        DispatchQueue.main.async {
            self.messages.append(ChatMessage(role: role, text: text))
            if self.messages.count > 12 {
                self.messages.removeFirst(self.messages.count - 12)
            }
        }
    }

    // MARK: - Audio Session

    private func configureAudioSessionForSpeech() throws {
        try audioSession.setCategory(.playAndRecord,
                                     mode: .spokenAudio,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func cleanupAfterFailedStart() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        cancelSilenceTimer()
        isListening = false
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

