import XCTest
import DossivoixCore
@testable import Dossivoix

@MainActor
final class SpeechRecognitionInputTests: XCTestCase {
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
        session.callbacks[0]("oui", false, false)
        session.callbacks[0](nil, false, true)
        session.callbacks[1]("non", true, false)
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
    var callbacks: [@MainActor (String?, Bool, Bool) -> Void] = []
    var stops = 0
    var shouldThrow = false
    struct Failure: Error {}
    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool) -> Void) throws {
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
