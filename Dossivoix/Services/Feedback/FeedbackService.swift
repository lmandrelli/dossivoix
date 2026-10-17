import AVFoundation
import UIKit
import DossivoixCore

/// Petits signaux sonores et haptiques, derrière un protocole pour pouvoir les simuler.
@MainActor
protocol FeedbackPlaying: AnyObject {
    /// Joue le signal et ne rend la main qu'une fois le son terminé.
    func play(_ cue: FeedbackCue) async
}

/// Signaux simulés : rien n'est joué.
final class SilentFeedback: FeedbackPlaying {
    private(set) var playedCues: [FeedbackCue] = []

    func play(_ cue: FeedbackCue) async {
        playedCues.append(cue)
    }
}

/// Signaux réels : vibration (Taptic Engine) + sons générés par le code
/// (aucun fichier audio, aucun son système non documenté).
@MainActor
final class SoundAndHapticFeedback: FeedbackPlaying {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var buffers: [FeedbackCue: AVAudioPCMBuffer] = [:]

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ cue: FeedbackCue) async {
        playHaptic(for: cue)
        guard let buffer = buffer(for: cue) else { return }

        do {
            try engine.start()
        } catch {
            Log.audio.error("Démarrage du moteur audio impossible : \(error.localizedDescription)")
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
                continuation.resume()
            }
            player.play()
        }
        // Moteur arrêté entre deux signaux : il ne doit pas occuper l'audio pendant l'écoute
        // ni empêcher la désactivation de la session audio.
        player.stop()
        engine.stop()
    }

    private func playHaptic(for cue: FeedbackCue) {
        switch cue {
        case .listening:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Échantillons du signal, calculés une seule fois.
    private func buffer(for cue: FeedbackCue) -> AVAudioPCMBuffer? {
        if let buffer = buffers[cue] { return buffer }

        let samples = ToneSynthesizer.samples(for: cue.notes, sampleRate: format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffers[cue] = buffer
        return buffer
    }
}
