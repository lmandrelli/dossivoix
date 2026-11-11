import XCTest
@testable import DossivoixCore

final class LongDictationTests: XCTestCase {
    func testSuffixCommandsAndLiteralEscape() {
        XCTAssertEqual(DictationCommand.action(in: "Factures été terminer la dictée."), .finish("Factures été"))
        XCTAssertNil(DictationCommand.action(in: "Comment terminer la dictée demain"))
        XCTAssertNil(DictationCommand.action(in: "texte littéral terminer la dictée"))
        XCTAssertEqual(DictationCommand.content("texte littéral annuler"), "annuler")
        XCTAssertEqual(DictationCommand.action(in: "Factures annuler la dictée"), .cancel("Factures"))
        XCTAssertEqual(DictationCommand.action(in: "stop"), .cancel(""))
    }

    func testInterruptedSegmentsResumeWithoutLossAndRequireConfirmation() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.paused("Factures")))
        XCTAssertEqual(machine.state, .confirmingName(name: "Factures", attempt: 1, target: .anyTag))
        XCTAssertEqual(machine.handle(.heard(.text("encore"))).last, .listen(.name))
        _ = machine.handle(.heard(.paused("été")))
        _ = machine.handle(.screenAnswer(.again))
        let effects = machine.handle(.heard(.dictated("2026")))
        XCTAssertEqual(machine.state, .confirmingName(name: "Factures été 2026", attempt: 1, target: .anyTag))
        XCTAssertEqual(effects.last, .listen(.answer))
        XCTAssertFalse(effects.contains { if case .writeTag = $0 { true } else { false } })
        XCTAssertTrue(machine.handle(.screenAnswer(.yes)).contains { if case .writeTag = $0 { true } else { false } })
    }

    func testLiteralCancelIsContentAndCancelDiscardsDraft() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated("annuler")))
        XCTAssertEqual(machine.state, .confirmingName(name: "Annuler", attempt: 1, target: .anyTag))
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.paused("Ancien")))
        _ = machine.handle(.stopVoice(partial: ""))
        XCTAssertEqual(machine.dictationDraft, "")
        XCTAssertEqual(machine.state, .confirmingName(name: "Ancien", attempt: 1, target: .anyTag))
        _ = machine.handle(.abandonWriting)
        XCTAssertEqual(machine.state, .idle)
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated("Nouveau")))
        XCTAssertEqual(machine.state, .confirmingName(name: "Nouveau", attempt: 1, target: .anyTag))
    }

    func testResumeUnavailableKeepsDraftWithoutKeyboard() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.paused("Texte conservé")))
        _ = machine.handle(.screenAnswer(.again))
        XCTAssertEqual(machine.handle(.heard(.unavailable)), [.say(Phrases.voiceUnavailable, cue: .error)])
        XCTAssertEqual(machine.state, .pausedDictation(text: "Texte conservé", target: .anyTag))
    }

    func testStopVoiceDuringConfirmationKeepsQuestionWithoutWriting() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated("Factures")))
        XCTAssertEqual(machine.handle(.stopVoice(partial: "")), [])
        XCTAssertEqual(machine.state, .confirmingName(name: "Factures", attempt: 1, target: .anyTag))
        XCTAssertTrue(machine.handle(.screenAnswer(.yes)).contains { if case .writeTag = $0 { true } else { false } })
    }

    func testAutomaticStopReadsBackAndDoesNotWrite() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        XCTAssertEqual(machine.handle(.heard(.paused("factures"))),
                       [.say(Phrases.confirmName("Factures"), cue: nil), .listen(.answer)])
        XCTAssertEqual(machine.state, .confirmingName(name: "Factures", attempt: 1, target: .anyTag))
    }

    func testVoiceButtonRepeatsConfirmationWithoutWriting() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated("Banque")))
        _ = machine.handle(.heard(.unavailable))
        XCTAssertEqual(machine.handle(.resumeVoice),
                       [.say(Phrases.confirmName("Banque"), cue: nil), .listen(.answer)])
        XCTAssertEqual(machine.state, .confirmingName(name: "Banque", attempt: 1, target: .anyTag))
    }

    func testVoiceButtonAtRestOffersActionsWithoutOpeningNFC() {
        var machine = FlowMachine()
        XCTAssertEqual(machine.handle(.resumeVoice), [.say(Phrases.voiceMenu, cue: nil), .listen(.answer)])
        XCTAssertEqual(machine.handle(.heard(.text("lire"))), [.readTag])
        XCTAssertEqual(machine.handle(.resumeVoice), []) // NFC en cours : ne pas relancer.
    }

    func testCapacityUsesUTF8AndKeepsOversizedText() {
        let text = String(repeating: "😀", count: 40)
        XCTAssertFalse(CapacityCheck(folderName: text).fits)
        XCTAssertTrue(CapacityCheck(folderName: String(repeating: "a", count: 40)).fits)
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated(text)))
        let effects = machine.handle(.screenAnswer(.yes))
        XCTAssertEqual(machine.state, .confirmingName(name: text, attempt: 1, target: .anyTag))
        XCTAssertFalse(effects.contains { if case .writeTag = $0 { true } else { false } })
    }
}
