import Foundation
import Observation
import UIKit
import DossivoixCore

/// Remplacement en attente de confirmation : l'étiquette contenait déjà autre chose.
struct PendingReplace: Equatable {
    /// Nom à écrire.
    let name: String
    /// Contenu vu au 1er passage : au 2e passage, on n'écrit que si l'étiquette le contient toujours.
    let seenContent: [NDEFRecord]
}

/// Chef d'orchestre des parcours de l'app.
///
/// Étape 4 : lecture et écriture guidées à la voix, saisie du nom au clavier,
/// confirmation de remplacement à l'écran. La dictée, les réponses vocales et la machine
/// à états complète viendront ensuite.
@MainActor
@Observable
final class FlowCoordinator {
    /// Dernier message, affiché en grand à l'écran et prononcé.
    private(set) var statusMessage = Phrases.welcome
    /// Vrai pendant un parcours : les boutons sont désactivés.
    private(set) var isBusy = false
    /// Remplacement à confirmer : l'écran affiche alors « Remplacer » et « Annuler ».
    private(set) var pendingReplace: PendingReplace?

    let diagnostics: DiagnosticLog
    private let tags: TagReading & TagWriting
    private let speech: SpeechOutput
    private let feedback: FeedbackPlaying
    private let audioSession: AudioSessionControlling
    private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        tags: TagReading & TagWriting,
        speech: SpeechOutput,
        feedback: FeedbackPlaying,
        audioSession: AudioSessionControlling,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { false },
        diagnostics: DiagnosticLog? = nil
    ) {
        self.tags = tags
        self.speech = speech
        self.feedback = feedback
        self.audioSession = audioSession
        self.isVoiceOverRunning = isVoiceOverRunning
        self.diagnostics = diagnostics ?? DiagnosticLog()
    }

    /// Coordinateur réel : CoreNFC, synthèse vocale, sons et vibrations.
    static func live() -> FlowCoordinator {
        FlowCoordinator(
            tags: makeTagService(),
            speech: AdaptiveSpeechOutput.live(),
            feedback: SoundAndHapticFeedback(),
            audioSession: AudioSessionManager(),
            isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }

    /// Service NFC réel ; en Debug, l'argument de lancement `-FakeNFC` le remplace par
    /// une simulation (lecture d'une étiquette SmartVision, puis remplacement confirmé),
    /// pour essayer les écrans dans le simulateur.
    private static func makeTagService() -> TagReading & TagWriting {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FakeNFC") {
            let existing = SmartVisionFormat.standard.records(forFolderName: "Dossier panneau solaire")
            return FakeTagService(
                readResult: .success(existing),
                writeResults: [
                    .success(.needsReplaceConfirmation(current: existing)),
                    .success(.written(previous: existing)),
                ]
            )
        }
        #endif
        return CoreNFCTagService()
    }

    // MARK: - Lecture

    func startReading() async {
        await runFlow {
            let result = await self.withApproachPrompt(Phrases.approachTag) {
                await self.tags.readTag()
            }
            switch result {
            case .success(let records):
                let decoded = TagDecoder.decode(records)
                self.diagnostics.add(decoded)
                await self.announce(Phrases.readResult(decoded), cue: decoded.folderName == nil ? .error : .success)
            case .failure(let error):
                await self.announce(error, during: .reading)
            }
        }
    }

    // MARK: - Écriture

    /// 1er passage : vérifie le nom, puis écrit directement si l'étiquette est vide ;
    /// sinon demande confirmation avant de remplacer.
    func startWriting(folderName: String) async {
        let name = FolderName.preparedForWriting(folderName)
        guard !name.isEmpty else { return }
        pendingReplace = nil

        await runFlow {
            // Vérification de la taille avant même d'approcher l'étiquette (NTAG 213).
            let check = CapacityCheck(folderName: name)
            guard check.fits else {
                await self.announce(Phrases.nameTooLong(check), cue: .error)
                return
            }
            await self.write(name: name, expectedCurrent: nil)
        }
    }

    /// 2e passage, après confirmation : n'écrit que si l'étiquette n'a pas changé.
    func confirmReplace() async {
        guard let pending = pendingReplace else { return }
        pendingReplace = nil
        await runFlow {
            await self.write(name: pending.name, expectedCurrent: pending.seenContent)
        }
    }

    /// Refus du remplacement : l'étiquette reste telle quelle.
    func cancelReplace() async {
        guard pendingReplace != nil else { return }
        pendingReplace = nil
        await runFlow {
            await self.announce(Phrases.writeCanceledTagUnchanged, cue: nil)
        }
    }

    private func write(name: String, expectedCurrent: [NDEFRecord]?) async {
        let records = SmartVisionFormat.standard.records(forFolderName: name)
        let isSecondPass = expectedCurrent != nil
        let result = await withApproachPrompt(isSecondPass ? Phrases.approachTagAgain : Phrases.approachTag) {
            await self.tags.writeTag(records: records, expectedCurrent: expectedCurrent, isSecondPass: isSecondPass)
        }

        switch result {
        case .success(.written):
            await announce(Phrases.written(name), cue: .success)
        case .success(.alreadyUpToDate):
            await announce(Phrases.alreadyWritten(name), cue: .success)
        case .success(.needsReplaceConfirmation(let current)):
            let existing = TagDecoder.decode(current)
            diagnostics.add(existing)
            pendingReplace = PendingReplace(name: name, seenContent: current)
            await announce(Phrases.askReplace(existing: existing, newName: name), cue: nil)
        case .failure(.userCanceled):
            await announce(Phrases.writeCanceledTagUnchanged, cue: nil)
        case .failure(let error):
            await announce(error, during: .writing)
        }
    }

    // MARK: - Arrêt

    /// Coupe la parole (app mise en arrière-plan, par exemple).
    func stopSpeaking() {
        speech.stop()
    }

    // MARK: - Outils

    /// Encadre un parcours : un seul à la fois, session audio active pendant sa durée.
    private func runFlow(_ body: () async -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        audioSession.activate()
        await body()
        audioSession.deactivate()
        isBusy = false
    }

    /// Prononce la consigne pendant que la feuille NFC s'ouvre, puis la coupe dès que
    /// l'étiquette est traitée (ou que le NFC est indisponible).
    /// Avec VoiceOver, la feuille NFC est déjà lue : la consigne est omise (voir VoiceSettings).
    private func withApproachPrompt<Value>(_ prompt: String, _ operation: () async -> Value) async -> Value {
        statusMessage = prompt
        let speaking = Task {
            let skipped = VoiceSettings.skipsApproachPromptWithVoiceOver && isVoiceOverRunning()
            if !skipped && !Task.isCancelled {
                await speech.speak(prompt)
            }
        }
        let value = await operation()
        speaking.cancel()
        speech.stop()
        await speaking.value
        return value
    }

    /// Affiche le message, joue le signal éventuel, puis prononce le message.
    private func announce(_ text: String, cue: FeedbackCue?) async {
        statusMessage = text
        if let cue {
            await feedback.play(cue)
        }
        await speech.speak(text)
    }

    /// Annonce une erreur NFC ; une annulation volontaire n'a pas de signal d'erreur.
    private func announce(_ error: TagError, during operation: Phrases.Operation) async {
        await announce(Phrases.message(for: error, during: operation), cue: error == .userCanceled ? nil : .error)
    }
}
