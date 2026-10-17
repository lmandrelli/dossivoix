import Foundation

/// Une note d'un petit signal sonore. Une fréquence de 0 représente un silence.
public struct Note: Equatable, Sendable {
    /// Fréquence en hertz.
    public let frequency: Double
    /// Durée en secondes.
    public let duration: Double

    public init(_ frequency: Double, _ duration: Double) {
        self.frequency = frequency
        self.duration = duration
    }
}

/// Signaux sonores (et haptiques) distincts, pour savoir où on en est sans regarder l'écran.
public enum FeedbackCue: Sendable, CaseIterable {
    /// « J'écoute » : deux notes brèves montantes, juste avant d'ouvrir le micro.
    case listening
    /// Succès : trois notes montantes.
    case success
    /// Erreur : deux notes graves descendantes.
    case error

    public var notes: [Note] {
        switch self {
        case .listening:
            [Note(587, 0.08), Note(880, 0.10)]
        case .success:
            [Note(660, 0.09), Note(880, 0.09), Note(1320, 0.18)]
        case .error:
            [Note(440, 0.16), Note(0, 0.05), Note(311, 0.28)]
        }
    }

    /// Durée totale du signal, en secondes.
    public var duration: Double {
        notes.reduce(0) { $0 + $1.duration }
    }
}

/// Fabrique les échantillons audio des signaux : sinusoïdes avec un court fondu
/// au début et à la fin de chaque note, pour éviter les claquements.
public enum ToneSynthesizer {
    public static func samples(
        for notes: [Note],
        sampleRate: Double,
        amplitude: Float = 0.35,
        fadeDuration: Double = 0.01
    ) -> [Float] {
        var samples: [Float] = []
        for note in notes {
            let count = Int((note.duration * sampleRate).rounded())
            let fadeCount = max(Int(fadeDuration * sampleRate), 1)
            for index in 0..<count {
                guard note.frequency > 0 else {
                    samples.append(0)
                    continue
                }
                let time = Double(index) / sampleRate
                let wave = Float(sin(2 * Double.pi * note.frequency * time))
                // Enveloppe : montée et descente linéaires sur `fadeCount` échantillons.
                let envelope = min(Float(index) / Float(fadeCount), Float(count - 1 - index) / Float(fadeCount), 1)
                samples.append(wave * amplitude * max(envelope, 0))
            }
        }
        return samples
    }
}
