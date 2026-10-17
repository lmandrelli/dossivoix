import Foundation
import Observation
import UIKit
import DossivoixCore

/// Chef d'orchestre des parcours de l'app.
///
/// Étape 3 : lecture guidée à la voix, avec signaux sonores et haptiques.
/// L'écriture, la dictée et la machine à états complète viendront ensuite.
@MainActor
@Observable
final class FlowCoordinator {
    /// Dernier message, affiché en grand à l'écran et prononcé.
    private(set) var statusMessage = Phrases.welcome
    /// Vrai pendant un parcours : les boutons sont désactivés.
    private(set) var isBusy = false

    let diagnostics: DiagnosticLog
    private let tagReader: TagReading
    private let speech: SpeechOutput
    private let feedback: FeedbackPlaying
    private let audioSession: AudioSessionControlling
    private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        tagReader: TagReading,
        speech: SpeechOutput,
        feedback: FeedbackPlaying,
        audioSession: AudioSessionControlling,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { false },
        diagnostics: DiagnosticLog? = nil
    ) {
        self.tagReader = tagReader
        self.speech = speech
        self.feedback = feedback
        self.audioSession = audioSession
        self.isVoiceOverRunning = isVoiceOverRunning
        self.diagnostics = diagnostics ?? DiagnosticLog()
    }

    /// Coordinateur réel : CoreNFC, synthèse vocale, sons et vibrations.
    static func live() -> FlowCoordinator {
        FlowCoordinator(
            tagReader: CoreNFCTagService(),
            speech: AdaptiveSpeechOutput.live(),
            feedback: SoundAndHapticFeedback(),
            audioSession: AudioSessionManager(),
            isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }

    // MARK: - Lecture

    func startReading() async {
        guard !isBusy else { return }
        isBusy = true
        audioSession.activate()
        defer {
            audioSession.deactivate()
            isBusy = false
        }

        // La consigne est prononcée pendant que la feuille NFC s'ouvre.
        statusMessage = Phrases.approachTag
        let prompt = Task {
            let skipped = VoiceSettings.skipsApproachPromptWithVoiceOver && isVoiceOverRunning()
            if !skipped && !Task.isCancelled {
                await speech.speak(Phrases.approachTag)
            }
        }
        let result = await tagReader.readTag()
        // Étiquette lue très vite (ou NFC indisponible) : on coupe ou on saute la consigne
        // pour annoncer directement le résultat.
        prompt.cancel()
        speech.stop()
        await prompt.value

        switch result {
        case .success(let records):
            let decoded = TagDecoder.decode(records)
            diagnostics.add(decoded)
            await announce(Phrases.readResult(decoded), cue: decoded.folderName == nil ? .error : .success)
        case .failure(.userCanceled):
            // Annulation volontaire : pas de signal d'erreur.
            await announce(Phrases.message(for: .userCanceled, during: .reading), cue: nil)
        case .failure(let error):
            await announce(Phrases.message(for: error, during: .reading), cue: .error)
        }
    }

    // MARK: - Écriture (étape 4)

    func startWriting(folderName: String) async {
        guard !isBusy else { return }
        isBusy = true
        audioSession.activate()
        defer {
            audioSession.deactivate()
            isBusy = false
        }
        await announce("L'écriture sera disponible dans une prochaine version.", cue: nil)
    }

    // MARK: - Arrêt

    /// Coupe la parole (app mise en arrière-plan, par exemple).
    func stopSpeaking() {
        speech.stop()
    }

    // MARK: - Outils

    /// Affiche le message, joue le signal éventuel, puis prononce le message.
    private func announce(_ text: String, cue: FeedbackCue?) async {
        statusMessage = text
        if let cue {
            await feedback.play(cue)
        }
        await speech.speak(text)
    }
}
