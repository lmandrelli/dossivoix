import XCTest
@testable import Dossivoix

final class DictationTranscriptTests: XCTestCase {
    func testPartialRevisionsCanShortenTextWithoutAppending() {
        var transcript = DictationTranscript()
        _ = transcript.receive("Les documents et", utterance: nil)
        XCTAssertEqual(transcript.receive("Les documents", utterance: nil), "Les documents")
        XCTAssertEqual(transcript.receive("Mes documents", utterance: nil), "Mes documents")
    }

    func testCompletedUtteranceDuplicatesAndCorrectionsDoNotDuplicateText() {
        var transcript = DictationTranscript()
        let range = SpeechUtterance(start: 1, end: 3, isComplete: true)
        _ = transcript.receive("Les documents", utterance: range)
        XCTAssertEqual(transcript.receive("Les documents", utterance: range), "Les documents")
        XCTAssertEqual(transcript.receive("Mes documents", utterance: range), "Mes documents")
        XCTAssertEqual(transcript.receive("Mes documents", utterance: nil), "Mes documents")
        XCTAssertEqual(transcript.receive("de famille", utterance: nil), "Mes documents de famille")
    }

    func testCumulativeResultsAfterBoundaryDoNotDuplicatePrefix() {
        var transcript = DictationTranscript()
        _ = transcript.receive("Début", utterance: SpeechUtterance(start: 1, end: 2, isComplete: true))
        XCTAssertEqual(transcript.receive("Début et suite", utterance: nil), "Début et suite")
        XCTAssertEqual(transcript.receive("Début et suite", utterance:
            SpeechUtterance(start: 1, end: 5, isComplete: true)), "Début et suite")
        XCTAssertEqual(transcript.receive("fin", utterance: nil), "Début et suite fin")
    }

    func testRepeatedWordsAtDifferentAudioTimesArePreserved() {
        var transcript = DictationTranscript()
        _ = transcript.receive("Très", utterance: SpeechUtterance(start: 1, end: 2, isComplete: true))
        XCTAssertEqual(transcript.receive("Très", utterance:
            SpeechUtterance(start: 5, end: 6, isComplete: true)), "Très Très")
        XCTAssertEqual(transcript.receive("important", utterance: nil), "Très Très important")
    }

    func testTimedPartialNewUtteranceAndRevisionKeepPreviousPhrase() {
        var transcript = DictationTranscript()
        _ = transcript.receive("Début", utterance: SpeechUtterance(start: 1, end: 2, isComplete: false))
        XCTAssertEqual(transcript.receive("suit", utterance:
            SpeechUtterance(start: 5, end: 6, isComplete: false)), "Début suit")
        XCTAssertEqual(transcript.receive("suite", utterance:
            SpeechUtterance(start: 5, end: 6, isComplete: true)), "Début suite")
    }
}
