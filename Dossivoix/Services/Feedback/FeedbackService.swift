import AVFoundation
import UIKit
import DossivoixCore

/// Petits signaux sonores et haptiques, derrière un protocole pour pouvoir les simuler.
@MainActor
protocol FeedbackPlaying: AnyObject {
    /// Joue le signal et ne rend la main qu'une fois le son terminé.
    func play(_ cue: FeedbackCue) async
    func stop()
}

/// Signaux simulés : rien n'est joué.
final class SilentFeedback: FeedbackPlaying {
    func stop() {}
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
    private var playbackID: UUID?
    private var continuation: CheckedContinuation<Void, Never>?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ cue: FeedbackCue) async {
        stop()
        playHaptic(for: cue)
        guard let buffer = buffer(for: cue) else { return }

        do {
            try engine.start()
        } catch {
            Log.audio.error("Démarrage du moteur audio impossible : \(error.localizedDescription)")
            return
        }
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.playbackID = id
            self.continuation = continuation
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.finish(id) }
            }
            player.play()
        }
    }

    func stop() {
        if let playbackID { finish(playbackID) }
    }

    private func finish(_ id: UUID) {
        guard playbackID == id else { return }
        playbackID = nil
        let waiting = continuation
        continuation = nil
        player.stop()
        engine.stop()
        waiting?.resume()
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
