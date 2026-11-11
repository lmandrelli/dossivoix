import XCTest
@testable import DossivoixCore

final class FlowMachineTests: XCTestCase {
    private var machine = FlowMachine()
    private let smartVisionTag = SmartVisionFormat.standard.records(forFolderName: "Dossier panneau solaire")

    private func send(_ event: FlowEvent) -> [FlowEffect] {
        machine.handle(event)
    }

    private func heard(_ text: String) -> [FlowEffect] {
        machine.handle(.heard(.text(text)))
    }

    private func records(_ name: String) -> [NDEFRecord] {
        SmartVisionFormat.standard.records(forFolderName: name)
    }

    // MARK: - Lecture

    func testReadAnnouncesNameAndStops() {
        XCTAssertEqual(send(.startReading), [.readTag])
        XCTAssertEqual(machine.state, .reading)

        XCTAssertEqual(send(.readFinished(.success(smartVisionTag))), [
            .recordDiagnostic(smartVisionTag),
            .say("Dossier panneau solaire", cue: .success),
        ])
        XCTAssertEqual(machine.state, .idle)
    }

    func testNoAnswerAfterReadDoesNothingMore() {
        _ = send(.startReading)
        _ = send(.readFinished(.success(smartVisionTag)))
        XCTAssertEqual(send(.heard(.silence)), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEncoreReadsAgain() {
        _ = send(.startReading)
        _ = send(.readFinished(.success(smartVisionTag)))
        _ = send(.resumeVoice)
        XCTAssertEqual(heard("Encore"), [.readTag])
        XCTAssertEqual(machine.state, .reading)
    }

    func testReadErrorIsAnnouncedAndStops() {
        _ = send(.startReading)
        let effects = send(.readFinished(.failure(.tagRemoved)))
        XCTAssertEqual(effects.first, .say(Phrases.message(for: .tagRemoved, during: .reading), cue: .error))
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(machine.state, .idle)
    }

    func testReadCanceledOrUnavailableEnds() {
        _ = send(.startReading)
        XCTAssertEqual(send(.readFinished(.failure(.userCanceled))), [.say("Lecture annulée.", cue: nil)])
        XCTAssertEqual(machine.state, .idle)

        _ = send(.startReading)
        _ = send(.readFinished(.failure(.readingUnavailable)))
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Écriture

    func testRenamingUnknownOrMixedContentRequiresReplacementConsent() {
        let unknown = NDEFRecord(typeNameFormat: .wellKnown, type: Data("U".utf8),
                                payload: Data([0x03]) + Data("example.com".utf8))
        for current in [[unknown], records("Banque") + [unknown]] {
            machine = FlowMachine()
            _ = send(.startReading)
            _ = send(.readFinished(.success(current)))
            _ = send(.resumeVoice)
            _ = heard("écrire")
            _ = heard("assurance")
            let effects = heard("oui")
            XCTAssertEqual(machine.state, .confirmingReplace(name: "Assurance", seen: current, attempt: 1))
            XCTAssertEqual(effects, [
                .say(Phrases.askReplace(existing: TagDecoder.decode(current), newName: "Assurance"), cue: nil),
                .listen(.answer),
            ])
            XCTAssertEqual(heard("oui"), [
                .writeTag(records: records("Assurance"), expectedCurrent: current, isSecondPass: true),
            ])
        }
    }

    func testCanceledNFCWriteDoesNotPromiseUnchangedContent() {
        _ = send(.startWriting)
        _ = heard("banque")
        _ = heard("oui")
        XCTAssertEqual(send(.writeFinished(.failure(.userCanceled))),
                       [.say(Phrases.writeCanceledCheckTag, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testFullWriteOnEmptyTag() {
        XCTAssertEqual(send(.startWriting), [.say(Phrases.askName, cue: nil), .listen(.name)])

        XCTAssertEqual(heard("dossier panneau solaire"), [
            .say("J'ai compris : Dossier panneau solaire. C'est bon ?", cue: nil), .listen(.answer),
        ])

        XCTAssertEqual(heard("Oui c'est ça"), [
            .writeTag(records: smartVisionTag, expectedCurrent: nil, isSecondPass: false),
        ])

        XCTAssertEqual(send(.writeFinished(.success(.written(previous: [])))), [
            .say("Étiquette écrite : Dossier panneau solaire.", cue: .success),
        ])
        XCTAssertEqual(machine.state, .idle)

        XCTAssertEqual(heard("oui"), [])
    }

    func testNoOrRestartRelaunchesDictation() {
        _ = send(.startWriting)
        _ = heard("banque")
        XCTAssertEqual(heard("Non"), [.say(Phrases.askNameAgain, cue: nil), .listen(.name)])
        _ = heard("banques")
        XCTAssertEqual(heard("Recommencer"), [.say(Phrases.askNameAgain, cue: nil), .listen(.name)])
        if case .askingName = machine.state {} else { XCTFail("Dictée attendue") }
    }

    func testSpokenCancelDuringConfirmationOnlyStopsVoice() {
        _ = send(.startWriting)
        _ = heard("banque")
        XCTAssertEqual(heard("Annuler"), [.say(Phrases.voiceStopped, cue: nil)])
        XCTAssertEqual(machine.state, .confirmingName(name: "Banque", attempt: 1, target: .anyTag))
    }

    func testSpokenCancelDuringDictationKeepsDraft() {
        _ = send(.startWriting)
        XCTAssertEqual(heard("Annuler."), [.say(Phrases.voiceStoppedDraftKept, cue: nil)])
        XCTAssertEqual(machine.state, .pausedDictation(text: "", target: .anyTag))
        _ = send(.resumeVoice)
        XCTAssertEqual(send(.heard(.stopped("Factures"))), [.say(Phrases.voiceStoppedDraftKept, cue: nil)])
        XCTAssertEqual(machine.state, .pausedDictation(text: "Factures", target: .anyTag))
    }

    func testSilentDictationWaitsForVoiceButton() {
        _ = send(.startWriting)
        XCTAssertEqual(send(.heard(.silence)), [.say(Phrases.didNotHearNameRetry, cue: nil), .listen(.name)])
        XCTAssertEqual(send(.heard(.silence)), [.say(Phrases.didNotHearName, cue: .error)])
        XCTAssertEqual(machine.state, .pausedDictation(text: "", target: .anyTag))
    }

    func testUnclearConfirmationRepromptsThenFallsBackWithName() {
        _ = send(.startWriting)
        _ = heard("banque")
        let reprompt = heard("euh")
        XCTAssertEqual(reprompt.last, .listen(.answer))
        XCTAssertEqual(heard("hmm"), [.say(Phrases.useScreen, cue: .error)])
    }

    func testMicrophoneUnavailableWaitsForVoiceButton() {
        _ = send(.startWriting)
        XCTAssertEqual(send(.heard(.unavailable)),
                       [.say(Phrases.voiceUnavailable, cue: .error)])
    }

    func testTooLongNameAsksForShorterOne() {
        _ = send(.startWriting)
        _ = heard(String(repeating: "a", count: 120))
        let effects = heard("oui")
        XCTAssertEqual(effects.last, .listen(.answer))
        if case .say(let text, .error) = effects.first {
            XCTAssertTrue(text.hasSuffix(Phrases.shortenOrEdit))
        } else {
            XCTFail("Message d'erreur attendu")
        }
    }

    // MARK: - Remplacement

    private func reachReplaceQuestion() {
        _ = send(.startWriting)
        _ = heard("banque")
        _ = heard("oui")
        _ = send(.writeFinished(.success(.needsReplaceConfirmation(current: smartVisionTag))))
    }

    func testReplaceQuestionThenSecondPass() {
        _ = send(.startWriting)
        _ = heard("banque")
        _ = heard("oui")
        XCTAssertEqual(send(.writeFinished(.success(.needsReplaceConfirmation(current: smartVisionTag)))), [
            .recordDiagnostic(smartVisionTag),
            .say("Cette étiquette contient déjà : Dossier panneau solaire. Voulez-vous la remplacer par : Banque ?",
                 cue: nil),
            .listen(.answer),
        ])
        XCTAssertEqual(heard("oui"), [
            .writeTag(records: records("Banque"), expectedCurrent: smartVisionTag, isSecondPass: true),
        ])
    }

    func testRefusingReplaceKeepsTag() {
        reachReplaceQuestion()
        XCTAssertEqual(heard("non"), [.say(Phrases.writeCanceledTagUnchanged, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testReplaceByScreenButton() {
        reachReplaceQuestion()
        XCTAssertEqual(send(.screenAnswer(.yes)), [
            .writeTag(records: records("Banque"), expectedCurrent: smartVisionTag, isSecondPass: true),
        ])
    }

    func testUnclearReplaceAnswerEndsOnScreenButtons() {
        reachReplaceQuestion()
        XCTAssertEqual(heard("euh").last, .listen(.answer))
        XCTAssertEqual(heard("hmm"), [.say(Phrases.useScreenButtons, cue: .error)])
        // Les boutons restent utilisables.
        XCTAssertEqual(send(.heard(.silence)), [])
        XCTAssertEqual(send(.screenAnswer(.no)), [.say(Phrases.writeCanceledTagUnchanged, cue: nil)])
    }

    func testDifferentTagOnSecondPassOffersRetry() {
        reachReplaceQuestion()
        _ = heard("oui")
        let effects = send(.writeFinished(.failure(.differentTag)))
        XCTAssertEqual(effects, [.say(Phrases.message(for: .differentTag, during: .writing), cue: .error)])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(heard("encore"), [])
    }

    // MARK: - Renommage après lecture

    func testWriteAfterReadRenamesTheSameTag() {
        _ = send(.startReading)
        _ = send(.readFinished(.success(smartVisionTag)))
        _ = send(.resumeVoice)
        XCTAssertEqual(heard("écrire"), [
            .say(Phrases.askNewName(for: "Dossier panneau solaire"), cue: nil), .listen(.name),
        ])
        _ = heard("panneaux solaires")
        XCTAssertEqual(heard("oui"), [
            .writeTag(records: records("Panneaux solaires"), expectedCurrent: smartVisionTag, isSecondPass: false),
        ])
    }

    func testWriteAfterFailedReadIsANormalWrite() {
        _ = send(.startReading)
        _ = send(.readFinished(.failure(.timeout)))
        _ = send(.resumeVoice)
        XCTAssertEqual(heard("écrire"), [.say(Phrases.askName, cue: nil), .listen(.name)])
        XCTAssertEqual(machine.state, .askingName(attempt: 1, target: .anyTag))
    }

    func testNegativeReplacementCannotStartWriting() {
        for response in ["ne remplace pas", "je ne confirme pas", "pas correct", "surtout pas remplacer"] {
            machine = FlowMachine()
            reachReplaceQuestion()
            let effects = heard(response)
            XCTAssertFalse(effects.contains { if case .writeTag = $0 { return true }; return false }, response)
            guard case .confirmingReplace = machine.state else { return XCTFail(response) }
        }
    }

    func testRenameTargetSurvivesVoiceFailures() {
        for duringConfirmation in [false, true] {
            for unavailable in [false, true] {
                machine = FlowMachine()
                _ = send(.startReading)
                _ = send(.readFinished(.success(smartVisionTag)))
                _ = send(.resumeVoice)
                _ = heard("écrire")
                if duringConfirmation { _ = heard("banque") }
                if unavailable {
                    _ = send(.heard(.unavailable))
                } else {
                    _ = send(.heard(.silence))
                    _ = send(.heard(.silence))
                }
                if duringConfirmation {
                    XCTAssertEqual(machine.state, .confirmingName(name: "Banque", attempt: 3, target: .knownTag(expected: smartVisionTag, isSecondPass: false)))
                } else {
                    XCTAssertEqual(machine.state, .pausedDictation(text: "", target: .knownTag(expected: smartVisionTag, isSecondPass: false)))
                }
                if !duringConfirmation {
                    _ = send(.resumeVoice)
                    _ = send(.heard(.dictated("Banque")))
                }
                XCTAssertEqual(send(.screenAnswer(.yes)), [
                    .writeTag(records: records("Banque"), expectedCurrent: smartVisionTag, isSecondPass: false)
                ])
            }
        }
    }

    // MARK: - Divers

    func testAbandonWritingClearsDraftOnlyWhenWriting() {
        _ = send(.startWriting)
        _ = send(.heard(.paused("")))
        _ = send(.resumeVoice)
        _ = send(.stopVoice(partial: "Brouillon"))
        XCTAssertEqual(send(.abandonWriting), [.say(Phrases.writeCanceled, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.dictationDraft, "")
        XCTAssertEqual(send(.abandonWriting), [])
    }

    func testOutOfPlaceEventsAreIgnored() {
        XCTAssertEqual(send(.readFinished(.success([]))), [])
        XCTAssertEqual(send(.writeFinished(.success(.alreadyUpToDate))), [])
        XCTAssertEqual(heard("oui"), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEffectsWaitingForAResultComeLast() {
        reachReplaceQuestion()
        let effects = heard("euh")
        for effect in effects.dropLast() {
            switch effect {
            case .listen, .readTag, .writeTag: XCTFail("Effet bloquant avant la fin : \(effect)")
            default: break
            }
        }
    }
}
