import XCTest
@testable import DossivoixCore

/// Matrice des trois boutons, puis propriétés vérifiées sur tous les états atteignables
/// en quelques événements (boutons, voix, résultats NFC).
final class ScreenControlsTests: XCTestCase {
    private func records(_ name: String) -> [NDEFRecord] {
        SmartVisionFormat.standard.records(forFolderName: name)
    }

    private func actions(_ machine: FlowMachine, _ voice: VoiceActivity) -> [String] {
        machine.controls(voice: voice).slots.map { "\($0.action)\($0.isEnabled ? "" : " (inactif)")" }
    }

    // MARK: - Matrice

    func testMatrixFollowsTheJourney() {
        var machine = FlowMachine()
        XCTAssertEqual(actions(machine, .off), ["read", "write", "startVoice"])
        XCTAssertEqual(actions(machine, .speaking), ["read", "write", "stopVoice"])

        _ = machine.handle(.startReading)
        XCTAssertEqual(actions(machine, .off), ["read (inactif)", "write (inactif)", "startVoice (inactif)"])
        // La consigne « Approchez l'étiquette » ne se coupe pas par la voix : la feuille NFC a la main.
        XCTAssertEqual(actions(machine, .speaking), ["read (inactif)", "write (inactif)", "startVoice (inactif)"])

        _ = machine.handle(.startWriting)
        XCTAssertEqual(actions(machine, .speaking), ["finishDictation (inactif)", "abandonWriting", "stopVoice"])
        XCTAssertEqual(actions(machine, .listening), ["finishDictation", "abandonWriting", "stopVoice"])

        _ = machine.handle(.stopVoice(partial: ""))
        XCTAssertEqual(actions(machine, .off), ["finishDictation (inactif)", "abandonWriting", "startVoice"])
        _ = machine.handle(.resumeVoice)
        _ = machine.handle(.stopVoice(partial: "Factures"))
        XCTAssertEqual(actions(machine, .off), ["finishDictation", "abandonWriting", "startVoice"])

        _ = machine.handle(.finishDictation(partial: ""))
        XCTAssertEqual(actions(machine, .listening), ["confirmName", "restartDictation", "stopVoice"])

        _ = machine.handle(.screenAnswer(.yes))
        _ = machine.handle(.writeFinished(.success(.needsReplaceConfirmation(current: records("Banque")))))
        XCTAssertEqual(actions(machine, .listening), ["replace", "keepTag", "stopVoice"])
        XCTAssertEqual(actions(machine, .off), ["replace", "keepTag", "startVoice"])
    }

    func testTooLongNameCannotBeConfirmedByTouch() {
        var machine = FlowMachine()
        _ = machine.handle(.startWriting)
        _ = machine.handle(.heard(.dictated(String(repeating: "a", count: 120))))
        XCTAssertEqual(machine.controls(voice: .off).primary, ControlSlot(.confirmName, enabled: false))
        XCTAssertTrue(machine.controls(voice: .off).allows(.restartDictation))
    }

    // MARK: - Propriétés sur les états atteignables

    private static let unknown = NDEFRecord(typeNameFormat: .wellKnown, type: Data("U".utf8),
                                            payload: Data([0x03]) + Data("example.com".utf8))

    private var alphabet: [FlowEvent] {
        let tag = records("Banque")
        return [
            .startReading, .startWriting, .resumeVoice, .stopVoice(partial: "suite"),
            .finishDictation(partial: ""), .abandonWriting,
            .readFinished(.success(tag)), .readFinished(.success([Self.unknown])),
            .readFinished(.failure(.timeout)),
            .writeFinished(.success(.written(previous: []))),
            .writeFinished(.success(.needsReplaceConfirmation(current: tag))),
            .writeFinished(.failure(.differentTag)), .writeFinished(.failure(.userCanceled)),
            .heard(.text("oui")), .heard(.text("non")), .heard(.text("encore")), .heard(.text("écrire")),
            .heard(.text("annuler")), .heard(.text("euh")), .heard(.dictated("Factures")),
            .heard(.dictated(String(repeating: "a", count: 120))),
            .heard(.paused("été")), .heard(.stopped("mars")), .heard(.silence), .heard(.unavailable),
            .screenAnswer(.yes), .screenAnswer(.no), .screenAnswer(.restart), .screenAnswer(.again),
        ]
    }

    /// Toutes les machines atteignables depuis le repos en `depth` événements au plus.
    private func reachable(depth: Int = 5) -> [FlowMachine] {
        var seen: Set<String> = []
        var frontier = [FlowMachine()]
        var all: [FlowMachine] = []
        for _ in 0...depth {
            var next: [FlowMachine] = []
            for machine in frontier where seen.insert(String(describing: machine)).inserted {
                all.append(machine)
                for event in alphabet {
                    var copy = machine
                    _ = copy.handle(event)
                    next.append(copy)
                }
            }
            frontier = next
        }
        return all
    }

    private func draftText(_ machine: FlowMachine) -> String {
        switch machine.state {
        case .pausedDictation(let text, _): text
        case .confirmingName(let name, _, _): name
        default: machine.dictationDraft
        }
    }

    func testNoHiddenDraftOutsideWriting() {
        for machine in reachable() {
            switch machine.state {
            case .idle, .reading, .voiceMenu, .writing:
                XCTAssertEqual(machine.dictationDraft, "", "\(machine.state)")
            default: break
            }
        }
    }

    func testEveryReachableStateHasADistinctNonDestructiveWayOut() {
        let machines = reachable()
        XCTAssertGreaterThan(machines.count, 50)
        let kinds = Set(machines.map { "\($0.state)".prefix { $0 != "(" } })
        XCTAssertEqual(kinds, ["idle", "reading", "voiceMenu", "askingName", "pausedDictation",
                               "confirmingName", "writing", "confirmingReplace"])
        for machine in machines {
            for voice in [VoiceActivity.off, .speaking, .listening] {
                let controls = machine.controls(voice: voice)
                let context = "\(machine.state) / \(voice)"
                // Trois emplacements, trois sens différents : pas deux chemins vers le même résultat.
                XCTAssertEqual(Set(controls.slots.map { "\($0.action)" }).count, 3, context)
                if machine.state.isUsingTag {
                    XCTAssertFalse(controls.slots.contains { $0.isEnabled }, context)
                    continue
                }
                // Jamais bloqué : la voix peut toujours être relancée ou arrêtée au toucher.
                XCTAssertTrue(controls.voice.isEnabled, context)
                XCTAssertEqual(controls.voice.action, voice == .off ? .startVoice : .stopVoice, context)

                // Arrêter la voix ne lance rien, ne valide rien et ne perd aucun texte.
                var stopped = machine
                XCTAssertEqual(stopped.handle(.stopVoice(partial: "")), [], context)
                XCTAssertTrue(draftText(stopped).hasPrefix(draftText(machine)) || draftText(machine).isEmpty,
                              context)
                if case .voiceMenu = machine.state {} else if machine.state != .idle {
                    XCTAssertNotEqual(stopped.state, .idle, context)
                }

                // Un bouton actif fait toujours quelque chose (sauf Arrêter, coupé par l'app).
                for slot in controls.slots where slot.isEnabled && slot.action != .stopVoice {
                    if slot.action == .finishDictation && voice == .listening { continue }
                    var copy = machine
                    let effects = copy.handle(FlowMachine.event(for: slot.action))
                    XCTAssertTrue(!effects.isEmpty || copy.state != machine.state, "\(slot.action) — \(context)")
                }
            }
        }
    }

    func testWritingStartsOnlyFromAnExplicitConfirmation() {
        for machine in reachable() {
            for event in alphabet {
                var copy = machine
                let effects = copy.handle(event)
                guard let write = effects.first(where: { if case .writeTag = $0 { true } else { false } })
                else { continue }
                let context = "\(machine.state) + \(event)"
                XCTAssertTrue([FlowEvent.heard(.text("oui")), .screenAnswer(.yes)].contains(event), context)
                switch machine.state {
                case .confirmingName:
                    if case .writeTag(_, _, let secondPass) = write { XCTAssertFalse(secondPass, context) }
                case .confirmingReplace:
                    if case .writeTag(_, let expected, let secondPass) = write {
                        XCTAssertTrue(secondPass, context)
                        XCTAssertNotNil(expected, context)
                    }
                default:
                    XCTFail(context)
                }
            }
        }
    }

    func testOnlyAbandonOrKeepTagDiscardsTheWritingContext() {
        let destructive: [FlowEvent] = [.abandonWriting, .screenAnswer(.no), .heard(.text("non"))]
        for machine in reachable() {
            switch machine.state {
            case .askingName, .pausedDictation, .confirmingName, .confirmingReplace: break
            default: continue
            }
            for event in alphabet where !destructive.contains(event) {
                if case .startReading = event { continue } // Siri ou bouton Lire : autre parcours voulu.
                if case .startWriting = event { continue }
                if case .screenAnswer(.restart) = event { continue } // Recommencer : effacement explicite.
                if case .heard = event, !machine.isListeningContext { continue }
                var copy = machine
                _ = copy.handle(event)
                XCTAssertNotEqual(copy.state, .idle, "\(machine.state) + \(event)")
            }
        }
    }
}

private extension FlowMachine {
    /// États où un résultat d'écoute peut réellement arriver.
    var isListeningContext: Bool {
        switch state {
        case .askingName, .confirmingName, .confirmingReplace, .voiceMenu: true
        default: false
        }
    }
}
