import XCTest
import AVFoundation
import DossivoixCore
@testable import Dossivoix

@MainActor
final class FlowCoordinatorTests: XCTestCase {
    func testFailedReadIsAddedToDiagnostic() async {
        let coordinator = FlowCoordinator(tags: FakeTagService(readResult: .failure(.notNDEFCompatible)),
                                          speech: SpeechSpy(), speechInput: InputSpy(),
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startReading()
        await eventually { !coordinator.diagnostics.entries.isEmpty }
        XCTAssertEqual(coordinator.diagnostics.entries.count, 1)
        XCTAssertTrue(coordinator.diagnostics.fullReport.contains("notNDEFCompatible"))
        coordinator.stopAll()
    }

    func testCancelledReadDoesNotCreateAnErrorDiagnostic() async {
        let coordinator = FlowCoordinator(tags: FakeTagService(readResult: .failure(.userCanceled)),
                                          speech: SpeechSpy(), speechInput: InputSpy(),
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startReading()
        await drainTasks()
        XCTAssertTrue(coordinator.diagnostics.entries.isEmpty)
        coordinator.stopAll()
    }

    func testFailureDiagnosticKeepsDetailsAndCapacityLimit() {
        let log = DiagnosticLog()
        for index in 0...DiagnosticLog.capacity {
            log.addFailure(.unreadable, during: .reading, details: "Rapport \(index) : CC E1 10 3E 00")
        }
        XCTAssertEqual(log.entries.count, DiagnosticLog.capacity)
        XCTAssertTrue(log.entries[0].report.contains("Rapport 20 : CC E1 10 3E 00"))
        XCTAssertTrue(log.entries[0].hasUnrecognizedContent)
    }

    func testManualVoiceStopSoundsOnceAndKeepsDraft() async {
        let input = InputSpy()
        let feedback = SilentFeedback()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: feedback, audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { input.listens == 1 }
        XCTAssertEqual(feedback.playedCues, [.listening])
        input.currentText = "Texte conservé"
        coordinator.perform(.stopVoice)
        await eventually { feedback.playedCues.count == 2 }
        coordinator.perform(.stopVoice) // Appui périmé : aucun deuxième son.
        await drainTasks()
        XCTAssertEqual(feedback.playedCues, [.listening, .listeningEnded])
        XCTAssertEqual(coordinator.state, .pausedDictation(text: "Texte conservé", target: .anyTag))
    }

    func testNormalDictationEndSoundsBeforeNextListening() async {
        let input = InputSpy()
        let feedback = SilentFeedback()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: feedback, audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { input.listens == 1 }
        input.resolve(.dictated("Banque"))
        await eventually { input.listens == 2 }
        XCTAssertEqual(feedback.playedCues, [.listening, .listeningEnded, .listening])
        coordinator.stopAll() // Arrière-plan : pas de nouveau signal sonore.
        await drainTasks()
        XCTAssertEqual(feedback.playedCues, [.listening, .listeningEnded, .listening])
    }

    func testStopDuringSuccessCueCannotResumeSpeech() async {
        let speech = SpeechSpy()
        let feedback = SuspendedFeedback()
        let audio = AudioSpy()
        let coordinator = FlowCoordinator(
            tags: FakeTagService(readResult: .success(SmartVisionFormat.standard.records(forFolderName: "Banque"))),
            speech: speech, speechInput: InputSpy(), feedback: feedback, audioSession: audio
        )
        coordinator.startReading()
        await eventually { feedback.continuation != nil }
        coordinator.stopAll()
        speech.spoken.removeAll()
        feedback.complete() // Simule même un service qui finit malgré l'annulation.
        await drainTasks()
        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.isListening)
        XCTAssertFalse(audio.isActive)
    }

    func testStopDuringListeningCueCannotOpenMicrophone() async {
        let input = InputSpy()
        let feedback = SuspendedFeedback()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: feedback, audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { feedback.continuation != nil }
        coordinator.stopAll()
        feedback.complete()
        await drainTasks()
        XCTAssertEqual(input.listens, 0)
        XCTAssertFalse(coordinator.isListening)
    }

    func testLateNFCResultCannotSpeakAfterStop() async {
        let tags = SuspendedTags()
        let speech = SpeechSpy()
        let coordinator = FlowCoordinator(tags: tags, speech: speech, speechInput: InputSpy(),
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startReading()
        await eventually { tags.continuation != nil }
        coordinator.stopAll()
        speech.spoken.removeAll()
        tags.continuation?.resume(returning: .success(SmartVisionFormat.standard.records(forFolderName: "Ancien")))
        tags.continuation = nil
        await drainTasks()
        XCTAssertTrue(speech.spoken.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertGreaterThan(tags.cancels, 0)
    }

    func testBackgroundPreservesPartialAndLateCallbackCannotOverwriteIt() async {
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.currentText = "Factures été"
        coordinator.stopAll()
        await drainTasks()
        XCTAssertEqual(coordinator.state, .pausedDictation(text: "Factures été", target: .anyTag))
        XCTAssertFalse(coordinator.isListening)
        coordinator.perform(.startVoice)
        await eventually { coordinator.isListening }
        input.resolve(.dictated("2026"))
        await eventually {
            coordinator.state == .confirmingName(name: "Factures été 2026", attempt: 1, target: .anyTag)
        }
        coordinator.stopAll()
    }

    func testAudioInterruptionPreservesTextWithoutRestartingMicrophone() async {
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.currentText = "Conservé après appel"
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await drainTasks()
        XCTAssertEqual(coordinator.state, .pausedDictation(text: "Conservé après appel", target: .anyTag))
        XCTAssertEqual(input.listens, 1)
        XCTAssertFalse(coordinator.isListening)
        coordinator.stopAll()
    }

    func testStopDuringConfirmationDoesNotAppendAnswerHypothesisOrWrite() async {
        let input = InputSpy()
        let tags = SuspendedTags()
        let coordinator = FlowCoordinator(tags: tags, speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.resolve(.paused("Factures"))
        await eventually { input.listens == 2 && coordinator.isListening }
        input.currentText = "encore"
        coordinator.perform(.stopVoice)
        await drainTasks()
        XCTAssertEqual(coordinator.state, .confirmingName(name: "Factures", attempt: 1, target: .anyTag))
        XCTAssertEqual(coordinator.statusMessage, Phrases.confirmName("Factures"))
        XCTAssertEqual(coordinator.voiceActivity, .off)
        XCTAssertEqual(input.listens, 2)
        XCTAssertNil(tags.writeContinuation)
        XCTAssertEqual(coordinator.controls.primary, ControlSlot(.confirmName))
        XCTAssertEqual(coordinator.controls.voice, ControlSlot(.startVoice))
        // Voix répète la question, sans rien ajouter au nom.
        coordinator.perform(.startVoice)
        await eventually { input.listens == 3 }
        XCTAssertEqual(coordinator.state, .confirmingName(name: "Factures", attempt: 1, target: .anyTag))
        coordinator.stopAll()
    }

    func testListeningShowsStopAndVoiceCannotRelaunchListening() async {
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        XCTAssertEqual(coordinator.controls.voice, ControlSlot(.stopVoice))
        XCTAssertEqual(coordinator.controls.primary, ControlSlot(.finishDictation))
        coordinator.perform(.startVoice) // Appui tardif sur l'ancien bouton Voix : ignoré.
        coordinator.perform(.read)       // Lire n'est pas proposé pendant la dictée : ignoré.
        await drainTasks()
        XCTAssertEqual(input.listens, 1)
        XCTAssertTrue(coordinator.isListening)
        coordinator.stopAll()
    }

    func testStopVoiceDuringDictationKeepsTextThenFinishReadsItBack() async {
        let input = InputSpy()
        let tags = SuspendedTags()
        let audio = AudioSpy()
        let coordinator = FlowCoordinator(tags: tags, speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: audio)
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.ignoresCancel = true
        input.currentText = "Factures de janvier et février"
        coordinator.perform(.stopVoice)
        let paused = FlowState.pausedDictation(text: "Factures de janvier et février", target: .anyTag)
        XCTAssertEqual(coordinator.state, paused)
        XCTAssertEqual(coordinator.statusMessage, Phrases.dictationPaused("Factures de janvier et février"))
        XCTAssertFalse(audio.isActive)
        // Un résultat tardif de l'écoute coupée ne remplace ni ne valide le texte.
        input.resolve(.dictated("autre chose"))
        await drainTasks()
        XCTAssertEqual(coordinator.state, paused)
        XCTAssertEqual(input.listens, 1)
        input.ignoresCancel = false

        coordinator.perform(.finishDictation)
        await eventually { coordinator.isListening }
        XCTAssertEqual(coordinator.state,
                       .confirmingName(name: "Factures de janvier et février", attempt: 1, target: .anyTag))
        XCTAssertNil(tags.writeContinuation)
        coordinator.perform(.confirmName)
        await eventually { tags.writeContinuation != nil }
        coordinator.stopAll()
    }

    func testFinishWhileListeningUsesRecognizerTranscript() async {
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.currentText = "Impôts"
        coordinator.perform(.finishDictation)
        await eventually { input.listens == 2 }
        XCTAssertEqual(input.finishes, 1)
        XCTAssertEqual(coordinator.state, .confirmingName(name: "Impôts", attempt: 1, target: .anyTag))
        coordinator.stopAll()
    }

    func testAbandonIsTheOnlyTouchThatDiscardsTheDraft() async {
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { coordinator.isListening }
        input.currentText = "Brouillon"
        coordinator.perform(.abandonWriting)
        await drainTasks()
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.controls.primary, ControlSlot(.read))
        coordinator.perform(.startVoice)
        await eventually { coordinator.isListening }
        XCTAssertEqual(coordinator.state, .voiceMenu(lastRead: nil))
        coordinator.perform(.stopVoice)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testStopWhileSpeakingResultKeepsResultOnScreen() async {
        let speech = SuspendedSpeech(suspending: "Banque")
        let coordinator = FlowCoordinator(
            tags: FakeTagService(readResult: .success(SmartVisionFormat.standard.records(forFolderName: "Banque"))),
            speech: speech, speechInput: InputSpy(), feedback: SilentFeedback(), audioSession: AudioSpy()
        )
        coordinator.startReading()
        await eventually { speech.continuation != nil && coordinator.state == .idle }
        XCTAssertEqual(coordinator.voiceActivity, .speaking)
        XCTAssertEqual(coordinator.controls.voice, ControlSlot(.stopVoice))
        coordinator.perform(.stopVoice)
        XCTAssertGreaterThan(speech.stops, 0)
        XCTAssertEqual(coordinator.voiceActivity, .off)
        XCTAssertEqual(coordinator.statusMessage, "Banque")
        speech.complete()
        await drainTasks()
        XCTAssertEqual(coordinator.voiceActivity, .off)
    }

    func testStoppingCanceledWriteAnnouncementKeepsWarning() async {
        let tags = SuspendedTags()
        let input = InputSpy()
        let speech = SuspendedSpeech(suspending: Phrases.writeCanceledCheckTag)
        let coordinator = FlowCoordinator(tags: tags, speech: speech, speechInput: input,
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startWriting()
        await eventually { input.listens == 1 }
        input.resolve(.dictated("Banque"))
        await eventually { input.listens == 2 }
        coordinator.perform(.confirmName)
        await eventually { tags.writeContinuation != nil }
        tags.writeContinuation?.resume(returning: .failure(.userCanceled))
        tags.writeContinuation = nil
        await eventually { speech.continuation != nil }
        coordinator.perform(.stopVoice)
        XCTAssertEqual(coordinator.statusMessage, Phrases.writeCanceledCheckTag)
        speech.complete()
        await drainTasks()
        XCTAssertEqual(coordinator.statusMessage, Phrases.writeCanceledCheckTag)
    }

    func testVoiceButtonIsInactiveDuringNFC() async {
        let tags = SuspendedTags()
        let speech = SpeechSpy()
        let coordinator = FlowCoordinator(tags: tags, speech: speech, speechInput: InputSpy(),
                                          feedback: SilentFeedback(), audioSession: AudioSpy())
        coordinator.startReading()
        await eventually { tags.continuation != nil }
        XCTAssertEqual(coordinator.controls.voice, ControlSlot(.startVoice, enabled: false))
        let cancelsBefore = tags.cancels
        coordinator.perform(.stopVoice)
        coordinator.perform(.startVoice)
        coordinator.stopVoice()
        XCTAssertEqual(coordinator.state, .reading)
        XCTAssertEqual(tags.cancels, cancelsBefore) // La feuille NFC n'est pas fermée par la voix.
        coordinator.stopAll()
    }

    private func drainTasks() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func testInterruptedWriteKeepsWarningDespiteLateSuccess() async {
        let tags = SuspendedTags()
        let speech = SpeechSpy()
        let audio = AudioSpy()
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: tags, speech: speech, speechInput: input,
                                          feedback: SilentFeedback(), audioSession: audio)
        coordinator.startWriting()
        await eventually { input.listens == 1 }
        input.resolve(.dictated("Banque"))
        await eventually { input.listens == 2 }
        coordinator.perform(.confirmName)
        await eventually { tags.writeContinuation != nil }
        coordinator.stopAll()
        speech.spoken.removeAll()
        XCTAssertEqual(coordinator.statusMessage, Phrases.writeCanceledCheckTag)
        tags.writeContinuation?.resume(returning: .success(.written(previous: [])))
        tags.writeContinuation = nil
        await drainTasks()
        XCTAssertEqual(coordinator.statusMessage, Phrases.writeCanceledCheckTag)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(audio.isActive)
        XCTAssertTrue(speech.spoken.isEmpty)
    }
}

@MainActor
private final class SpeechSpy: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) async { spoken.append(text) }
    func stop() {}
}

@MainActor
private final class AudioSpy: AudioSessionControlling {
    var isActive = false
    func activate() async { isActive = true }
    func deactivate() { isActive = false }
}

@MainActor
private final class SuspendedSpeech: SpeechOutput {
    let suspendedText: String
    var continuation: CheckedContinuation<Void, Never>?
    var stops = 0
    init(suspending text: String) { suspendedText = text }
    func speak(_ text: String) async {
        guard text == suspendedText else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func stop() { stops += 1 } // Retour tardif volontaire : la parole « finit » après l'arrêt.
    func complete() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class InputSpy: SpeechInput {
    var currentText = ""
    var listens = 0
    var finishes = 0
    var continuation: CheckedContinuation<ListenResult, Never>?
    func listen(_ kind: ListenKind, onReady: @escaping @MainActor () async -> Void) async -> ListenResult {
        await onReady()
        guard !Task.isCancelled else { return .silence }
        listens += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finishDictation() {
        finishes += 1
        resolve(.dictated(currentText))
    }
    /// Résultat d'écoute, éventuellement tardif.
    func resolve(_ result: ListenResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
    /// Vrai : simule une reconnaissance qui rend encore un résultat après l'annulation.
    var ignoresCancel = false
    func cancel() {
        currentText = ""
        if !ignoresCancel { resolve(.silence) }
    }
}

@MainActor
private final class SuspendedFeedback: FeedbackPlaying {
    var continuation: CheckedContinuation<Void, Never>?
    func play(_ cue: FeedbackCue) async { await withCheckedContinuation { continuation = $0 } }
    func stop() {} // Retour tardif volontaire pour tester les protections du coordinateur.
    func complete() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class SuspendedTags: TagReading, TagWriting {
    var continuation: CheckedContinuation<Result<[NDEFRecord], TagError>, Never>?
    var writeContinuation: CheckedContinuation<Result<TagWriteOutcome, TagError>, Never>?
    var cancels = 0
    func readTag() async -> Result<[NDEFRecord], TagError> {
        await withCheckedContinuation { continuation = $0 }
    }
    func cancel() { cancels += 1 }
    func writeTag(records: [NDEFRecord], expectedCurrent: [NDEFRecord]?, isSecondPass: Bool) async -> Result<TagWriteOutcome, TagError> {
        await withCheckedContinuation { writeContinuation = $0 }
    }
}
