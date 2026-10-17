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

    func testReadAnnouncesNameThenOffersShortChoice() {
        XCTAssertEqual(send(.startReading), [.readTag])
        XCTAssertEqual(machine.state, .reading)

        XCTAssertEqual(send(.readFinished(.success(smartVisionTag))), [
            .recordDiagnostic(smartVisionTag),
            .say("Dossier panneau solaire", cue: .success),
            .say(Phrases.offerAfterRead, cue: nil),
            .listen(.answer),
        ])
        XCTAssertEqual(machine.state, .offeringAfterRead(lastRead: smartVisionTag))
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
        XCTAssertEqual(heard("Encore"), [.readTag])
        XCTAssertEqual(machine.state, .reading)
    }

    func testReadErrorIsAnnouncedAndStillOffersChoice() {
        _ = send(.startReading)
        let effects = send(.readFinished(.failure(.tagRemoved)))
        XCTAssertEqual(effects.first, .say(Phrases.message(for: .tagRemoved, during: .reading), cue: .error))
        XCTAssertEqual(effects.last, .listen(.answer))
        XCTAssertEqual(machine.state, .offeringAfterRead(lastRead: nil))
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
            .say(Phrases.offerAnotherWrite, cue: nil),
            .listen(.answer),
        ])
        XCTAssertEqual(machine.state, .offeringAnotherWrite)

        XCTAssertEqual(heard("oui"), [.say(Phrases.askName, cue: nil), .listen(.name)])
    }

    func testNoOrRestartRelaunchesDictation() {
        _ = send(.startWriting)
        _ = heard("banque")
        XCTAssertEqual(heard("Non"), [.say(Phrases.askNameAgain, cue: nil), .listen(.name)])
        _ = heard("banques")
        XCTAssertEqual(heard("Recommencer"), [.say(Phrases.askNameAgain, cue: nil), .listen(.name)])
        if case .askingName = machine.state {} else { XCTFail("Dictée attendue") }
    }

    func testCancelDuringConfirmation() {
        _ = send(.startWriting)
        _ = heard("banque")
        XCTAssertEqual(heard("Annuler"), [.say(Phrases.writeCanceled, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSayingCancelInsteadOfName() {
        _ = send(.startWriting)
        XCTAssertEqual(heard("Annuler."), [.say(Phrases.writeCanceled, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSilentDictationRetriesThenFallsBackToKeyboard() {
        _ = send(.startWriting)
        XCTAssertEqual(send(.heard(.silence)), [.say(Phrases.didNotHearName, cue: nil), .listen(.name)])
        XCTAssertEqual(send(.heard(.silence)), [.say(Phrases.useScreen, cue: .error), .showTextEntry(prefill: nil)])
        XCTAssertEqual(machine.state, .enteringName(target: .anyTag))
    }

    func testUnclearConfirmationRepromptsThenFallsBackWithName() {
        _ = send(.startWriting)
        _ = heard("banque")
        let reprompt = heard("euh")
        XCTAssertEqual(reprompt.last, .listen(.answer))
        XCTAssertEqual(heard("hmm"), [.say(Phrases.useScreen, cue: .error), .showTextEntry(prefill: "Banque")])
    }

    func testMicrophoneUnavailableFallsBackToKeyboard() {
        _ = send(.startWriting)
        XCTAssertEqual(send(.heard(.unavailable)),
                       [.say(Phrases.voiceUnavailable, cue: .error), .showTextEntry(prefill: nil)])
    }

    func testTooLongNameAsksForShorterOne() {
        _ = send(.startWriting)
        _ = heard(String(repeating: "a", count: 120))
        let effects = heard("oui")
        XCTAssertEqual(effects.last, .listen(.name))
        if case .say(let text, .error) = effects.first {
            XCTAssertTrue(text.hasSuffix(Phrases.askShorterName))
        } else {
            XCTFail("Message d'erreur attendu")
        }
    }

    func testTypedNameWritesWithoutVoiceConfirmation() {
        XCTAssertEqual(send(.typedName("  banque ")), [
            .writeTag(records: records("Banque"), expectedCurrent: nil, isSecondPass: false),
        ])
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
        XCTAssertEqual(send(.screenAnswer(.cancel)), [.say(Phrases.writeCanceledTagUnchanged, cue: nil)])
    }

    func testDifferentTagOnSecondPassOffersRetry() {
        reachReplaceQuestion()
        _ = heard("oui")
        let effects = send(.writeFinished(.failure(.differentTag)))
        XCTAssertEqual(effects.last, .listen(.answer))
        XCTAssertEqual(heard("encore"), [
            .writeTag(records: records("Banque"), expectedCurrent: smartVisionTag, isSecondPass: true),
        ])
    }

    // MARK: - Renommage après lecture

    func testWriteAfterReadRenamesTheSameTag() {
        _ = send(.startReading)
        _ = send(.readFinished(.success(smartVisionTag)))
        XCTAssertEqual(heard("écrire"), [
            .say("Dites le nouveau nom pour : Dossier panneau solaire.", cue: nil), .listen(.name),
        ])
        _ = heard("panneaux solaires")
        XCTAssertEqual(heard("oui"), [
            .writeTag(records: records("Panneaux solaires"), expectedCurrent: smartVisionTag, isSecondPass: false),
        ])
    }

    func testWriteAfterFailedReadIsANormalWrite() {
        _ = send(.startReading)
        _ = send(.readFinished(.failure(.timeout)))
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

    func testRenameTargetSurvivesAutomaticKeyboardFallbacks() {
        for duringConfirmation in [false, true] {
            for unavailable in [false, true] {
                machine = FlowMachine()
                _ = send(.startReading)
                _ = send(.readFinished(.success(smartVisionTag)))
                _ = heard("écrire")
                if duringConfirmation { _ = heard("banque") }
                if unavailable {
                    _ = send(.heard(.unavailable))
                } else {
                    _ = send(.heard(.silence))
                    _ = send(.heard(.silence))
                }
                XCTAssertEqual(machine.state, .enteringName(target: .knownTag(expected: smartVisionTag, isSecondPass: false)))
                XCTAssertEqual(send(.typedName("Banque")), [
                    .writeTag(records: records("Banque"), expectedCurrent: smartVisionTag, isSecondPass: false)
                ])
            }
        }
    }

    func testManualKeyboardPreservesReplacementTargetAndCancelClearsIt() {
        reachReplaceQuestion()
        _ = send(.requestTextEntry(prefill: "Banque"))
        XCTAssertEqual(send(.typedName("Impôts")), [
            .writeTag(records: records("Impôts"), expectedCurrent: smartVisionTag, isSecondPass: true)
        ])
        _ = send(.cancel)
        _ = send(.requestTextEntry(prefill: nil))
        XCTAssertEqual(send(.typedName("Nouveau")), [
            .writeTag(records: records("Nouveau"), expectedCurrent: nil, isSecondPass: false)
        ])
    }

    // MARK: - Divers

    func testScreenCancel() {
        _ = send(.startWriting)
        XCTAssertEqual(send(.cancel), [.say(Phrases.stopped, cue: nil)])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(send(.cancel), [])
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
