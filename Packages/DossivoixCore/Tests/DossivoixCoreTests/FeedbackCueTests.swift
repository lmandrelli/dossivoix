import XCTest
@testable import DossivoixCore

final class FeedbackCueTests: XCTestCase {
    func testCuesAreShortAndDistinct() {
        for cue in FeedbackCue.allCases {
            XCTAssertLessThan(cue.duration, 0.6, "\(cue) doit rester bref")
        }
        XCTAssertNotEqual(FeedbackCue.listening.notes, FeedbackCue.success.notes)
        XCTAssertNotEqual(FeedbackCue.success.notes, FeedbackCue.error.notes)
    }

    func testSampleCountMatchesDuration() {
        let samples = ToneSynthesizer.samples(for: FeedbackCue.success.notes, sampleRate: 44_100)
        XCTAssertEqual(Double(samples.count), FeedbackCue.success.duration * 44_100, accuracy: 3)
    }

    func testSamplesStayWithinAmplitudeAndStartSilent() {
        let samples = ToneSynthesizer.samples(for: [Note(880, 0.1)], sampleRate: 44_100, amplitude: 0.35)
        XCTAssertEqual(samples.first, 0)
        XCTAssertEqual(abs(samples.last ?? 1), 0, accuracy: 0.001)
        XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.35 })
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.3)
    }

    func testSilenceNote() {
        let samples = ToneSynthesizer.samples(for: [Note(0, 0.05)], sampleRate: 1_000)
        XCTAssertEqual(samples, Array(repeating: 0, count: 50))
    }
}
