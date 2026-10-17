import XCTest
import DossivoixCore
@testable import Dossivoix

@MainActor
final class FlowCoordinatorTests: XCTestCase {
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

    func testKeyboardStopsAudioAndBackgroundDismissesEntry() async {
        let audio = AudioSpy()
        let input = InputSpy()
        let coordinator = FlowCoordinator(tags: FakeTagService(), speech: SpeechSpy(), speechInput: input,
                                          feedback: SilentFeedback(), audioSession: audio)
        coordinator.startWriting()
        await eventually { input.listens == 1 }
        coordinator.openKeyboardEntry(prefill: "Banque")
        await eventually { coordinator.textEntryRequest != nil }
        XCTAssertFalse(audio.isActive)
        XCTAssertFalse(coordinator.isListening)
        XCTAssertEqual(coordinator.textEntryRequest?.prefill, "Banque")
        coordinator.stopAll()
        XCTAssertNil(coordinator.textEntryRequest)
        XCTAssertEqual(coordinator.state, .idle)
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

    private func drainTasks() async {
        for _ in 0..<10 { await Task.yield() }
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
private final class InputSpy: SpeechInput {
    var listens = 0
    var continuation: CheckedContinuation<ListenResult, Never>?
    func listen(_ kind: ListenKind) async -> ListenResult {
        listens += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func cancel() {
        continuation?.resume(returning: .silence)
        continuation = nil
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
    var cancels = 0
    func readTag() async -> Result<[NDEFRecord], TagError> {
        await withCheckedContinuation { continuation = $0 }
    }
    func cancel() { cancels += 1 }
    func writeTag(records: [NDEFRecord], expectedCurrent: [NDEFRecord]?, isSecondPass: Bool) async -> Result<TagWriteOutcome, TagError> {
        .failure(.readingUnavailable)
    }
}
