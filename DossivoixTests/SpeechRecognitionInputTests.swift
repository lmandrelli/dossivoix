import XCTest
import DossivoixCore
@testable import Dossivoix

@MainActor
final class SpeechRecognitionInputTests: XCTestCase {
    func testDeniedPermissionDoesNotPlayReadyCue() async {
        let input = SpeechRecognitionInput(session: RecognitionStub(), authorizeSpeech: { false },
                                           authorizeMicrophone: { true })
        var ready = false
        let result = await input.listen(.name, onReady: { ready = true })
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(ready)
    }

    func testCancelDuringReadyCueNeverStartsMicrophone() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true },
                                           authorizeMicrophone: { true })
        let result = await input.listen(.name, onReady: { input.cancel() })
        XCTAssertEqual(result, .silence)
        XCTAssertTrue(session.callbacks.isEmpty)
    }

    func testUtterancesAfterPausesKeepBeginningUntilVoiceFinish() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let listening = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("Factures de janvier", false, false,
                             SpeechUtterance(start: 0.4, end: 2, isComplete: true))
        // Apple repart sur un nouvel énoncé après la pause, sans isFinal.
        session.callbacks[0]("et février", false, false, nil)
        XCTAssertEqual(input.currentText, "Factures de janvier et février")
        session.callbacks[0]("et février", false, false,
                             SpeechUtterance(start: 8, end: 10, isComplete: true))
        session.callbacks[0]("terminer la dictée", true, false,
                             SpeechUtterance(start: 12, end: 14, isComplete: true))
        let result = await listening.value
        XCTAssertEqual(result, .dictated("Factures de janvier et février"))
    }

    func testSegmentedDictationPreservedOnErrorAndTouch() async {
        for failed in [false, true] {
            let session = RecognitionStub()
            let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
            let listening = Task { await input.listen(.name) }
            await eventually { session.callbacks.count == 1 }
            session.callbacks[0]("Début", false, false,
                                 SpeechUtterance(start: 1, end: 2, isComplete: true))
            session.callbacks[0]("suite provisoire", false, false, nil)
            session.callbacks[0]("suite corrigée", false, false, nil)
            if failed { session.callbacks[0](nil, false, true, nil) }
            else { input.finishDictation() }
            let result = await listening.value
            XCTAssertEqual(result, failed ? .paused("Début suite corrigée") : .dictated("Début suite corrigée"))
        }
    }

    func testSpokenCancelKeepsDictatedTextAndNewSessionIgnoresOldCallbacks() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let first = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("Ancien texte", false, false,
                             SpeechUtterance(start: 1, end: 2, isComplete: true))
        session.callbacks[0]("annuler la dictée", true, false, nil)
        let canceled = await first.value
        // « Annuler la dictée » arrête la voix sans perdre ce qui précède.
        XCTAssertEqual(canceled, .stopped("Ancien texte"))
        let second = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 2 }
        session.callbacks[0]("Ancien callback", false, false,
                             SpeechUtterance(start: 3, end: 4, isComplete: true))
        session.callbacks[1]("Nouveau terminer la dictée", true, false, nil)
        let result = await second.value
        XCTAssertEqual(result, .dictated("Nouveau"))
    }

    func testLongPauseDoesNotFinishAndPartialCommandCanBeRevised() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        var completed = false
        let listening = Task { let result = await input.listen(.name); completed = true; return result }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("Factures", false, false, nil)
        try? await Task.sleep(for: .seconds(16)) // dépasse aussi l’ancienne durée maximale de 15 secondes
        XCTAssertFalse(completed)
        session.callbacks[0]("Factures terminer la dictée", false, false, nil)
        session.callbacks[0]("Factures terminer la dictée demain", false, false, nil)
        try? await Task.sleep(for: .seconds(2))
        XCTAssertFalse(completed)
        session.callbacks[0]("Factures été terminer la dictée", false, false, nil)
        let result = await listening.value
        XCTAssertEqual(result, .dictated("Factures été"))
    }

    func testSystemFinalAndErrorPreservePartialWithoutValidation() async {
        for failed in [false, true] {
            let session = RecognitionStub()
            let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
            let listening = Task { await input.listen(.name) }
            await eventually { session.callbacks.count == 1 }
            session.callbacks[0]("Texte partiel", false, false, nil)
            session.callbacks[0](nil, !failed, failed, nil)
            let result = await listening.value
            XCTAssertEqual(result, .paused("Texte partiel"))
        }
    }

    func testDeadlinePreservesTextAndDoesNotValidate() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session,
            timingOverride: ListenTiming(initialTimeout: 1, silenceTimeout: 1, maxDuration: 0.1),
            authorizeSpeech: { true }, authorizeMicrophone: { true })
        let listening = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("Conservé", false, false, nil)
        let result = await listening.value
        XCTAssertEqual(result, .paused("Conservé"))
    }

    func testInactivityPausesAndKeepsLatestText() async {
        XCTAssertEqual(ListenKind.name.timing.silenceTimeout, 30)
        XCTAssertEqual(ListenKind.name.timing.initialTimeout, 30)
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session,
            timingOverride: ListenTiming(initialTimeout: 0.3, silenceTimeout: 0.15, maxDuration: 2),
            authorizeSpeech: { true }, authorizeMicrophone: { true })
        let listening = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("Factures", false, false, nil)
        try? await Task.sleep(for: .milliseconds(80))
        session.callbacks[0]("Factures été", false, false, nil)
        let result = await listening.value
        XCTAssertEqual(result, .paused("Factures été"))
    }

    func testInitialInactivityPausesWithoutInventingContent() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session,
            timingOverride: ListenTiming(initialTimeout: 0.05, silenceTimeout: 0.1, maxDuration: 2),
            authorizeSpeech: { true }, authorizeMicrophone: { true })
        let result = await input.listen(.name)
        XCTAssertEqual(result, .paused(""))
    }

    func testLiteralModeEndsByTouchAndVoiceCancellationWorks() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let first = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        session.callbacks[0]("texte littéral annuler", false, false, nil)
        input.finishDictation()
        let literal = await first.value
        XCTAssertEqual(literal, .dictated("annuler"))
        let second = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 2 }
        session.callbacks[1]("Contenu annuler la dictée", true, false, nil)
        let canceled = await second.value
        XCTAssertEqual(canceled, .stopped("Contenu"))
    }

    func testCancelDuringSpeechAuthorizationDoesNotAskForMicrophone() async {
        let authorization = PermissionGate()
        let session = RecognitionStub()
        var microphoneRequests = 0
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: {
            await authorization.wait()
        }, authorizeMicrophone: {
            microphoneRequests += 1
            return true
        })
        let listening = Task { await input.listen(.name) }
        await eventually { authorization.continuation != nil }
        input.cancel()
        authorization.resolve(true)
        let result = await listening.value
        XCTAssertEqual(result, .silence)
        XCTAssertEqual(microphoneRequests, 0)
        XCTAssertEqual(session.callbacks.count, 0)
    }

    func testCancelDuringMicrophoneAuthorizationDoesNotStartRecording() async {
        let authorization = PermissionGate()
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true },
                                          authorizeMicrophone: { await authorization.wait() })
        let listening = Task { await input.listen(.name) }
        await eventually { authorization.continuation != nil }
        input.cancel()
        authorization.resolve(true)
        let result = await listening.value
        XCTAssertEqual(result, .silence)
        XCTAssertTrue(session.callbacks.isEmpty)
    }

    func testOldCallbacksCannotFinishOrContaminateNextListening() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let first = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        let second = Task { await input.listen(.answer) }
        await eventually { session.callbacks.count == 2 }
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .silence)
        session.callbacks[0]("oui", false, false, nil)
        session.callbacks[0](nil, false, true, nil)
        session.callbacks[1]("non", true, false, nil)
        let secondResult = await second.value
        XCTAssertEqual(secondResult, .text("non"))
    }

    func testTaskCancellationStopsTheSession() async {
        let session = RecognitionStub()
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let listening = Task { await input.listen(.name) }
        await eventually { session.callbacks.count == 1 }
        let previousStops = session.stops
        listening.cancel()
        let result = await listening.value
        XCTAssertEqual(result, .silence)
        XCTAssertGreaterThan(session.stops, previousStops)
    }

    func testStartFailureStopsPartiallyStartedSession() async {
        let session = RecognitionStub()
        session.shouldThrow = true
        let input = SpeechRecognitionInput(session: session, authorizeSpeech: { true }, authorizeMicrophone: { true })
        let result = await input.listen(.name)
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(session.stops, 2) // Avant l'écoute, puis nettoyage après échec.
    }
}

@MainActor
private final class PermissionGate {
    var continuation: CheckedContinuation<Bool, Never>?
    func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
    func resolve(_ answer: Bool) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

@MainActor
private final class RecognitionStub: SpeechRecognitionSession {
    var isAvailable = true
    var callbacks: [@MainActor (String?, Bool, Bool, SpeechUtterance?) -> Void] = []
    var stops = 0
    var shouldThrow = false
    struct Failure: Error {}
    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool, SpeechUtterance?) -> Void) throws {
        callbacks.append(receive)
        if shouldThrow { throw Failure() }
    }
    func stop() { stops += 1 }
}

@MainActor
func eventually(file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async {
    for _ in 0..<200 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("L'événement attendu n'est pas arrivé", file: file, line: line)
}
