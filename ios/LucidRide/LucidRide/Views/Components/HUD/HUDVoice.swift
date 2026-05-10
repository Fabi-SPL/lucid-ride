import Foundation
import AVFoundation

/// AVSpeechSynthesizer-based TTS controller for the HUD.
/// Configures audio session to mix with music + duck other sources, so the
/// readout doesn't kill background playback. When a Cardo (or any Bluetooth
/// audio) device is connected, iOS routes the speech to it automatically.
@MainActor
final class HUDVoice: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    @Published var enabled: Bool = false

    init() { configure() }

    private func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                options: [.duckOthers, .mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("[HUDVoice] audio session setup failed: \(error)")
        }
    }

    func say(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.50
        u.pitchMultiplier = 1.0
        u.volume = 1.0
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func toggle() {
        enabled.toggle()
        if !enabled { stop() }
    }
}
