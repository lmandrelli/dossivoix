import XCTest
@testable import DossivoixCore

final class WritePlannerTests: XCTestCase {
    private let desired = SmartVisionFormat.standard.records(forFolderName: "Banque")
    private let capacity = TagCapacity.ntag213MaxMessageLength

    private func decide(
        status: TagWriteStatus = .readWrite,
        capacity: Int? = nil,
        current: [NDEFRecord],
        expected: [NDEFRecord]? = nil
    ) -> WriteDecision {
        WritePlanner.decide(status: status, capacity: capacity ?? self.capacity,
                            current: current, desired: desired, expectedCurrent: expected)
    }

    // MARK: 1er passage

    func testEmptyTagIsWrittenDirectly() {
        XCTAssertEqual(decide(current: []), .write)
        XCTAssertEqual(decide(current: [Fixtures.mediaText("  ")]), .write)
    }

    func testTagWithAnotherNameAsksForConfirmation() throws {
        let current = try NDEFCodec.decode(Fixtures.smartVisionMessage)
        guard case .askReplace(let existing) = decide(current: current) else {
            return XCTFail("Une confirmation est attendue")
        }
        XCTAssertEqual(existing.folderName, "Dossier panneau solaire")
    }

    func testUnrecognizedContentAsksForConfirmation() {
        let uri = NDEFRecord(typeNameFormat: .wellKnown, type: Data("U".utf8), payload: Data([0]))
        guard case .askReplace(let existing) = decide(current: [uri]) else {
            return XCTFail("Une confirmation est attendue")
        }
        XCTAssertEqual(existing.outcome, .unrecognized)
    }

    func testSameContentIsAlreadyUpToDate() {
        XCTAssertEqual(decide(current: desired), .alreadyUpToDate)
        XCTAssertEqual(decide(status: .readOnly, current: desired), .alreadyUpToDate)
    }

    func testSameNameInAnotherFormatIsRewrittenWithoutAsking() {
        XCTAssertEqual(decide(current: [Fixtures.wellKnownText("Banque")]), .write)
    }

    func testReadOnlyTagIsRefused() {
        XCTAssertEqual(decide(status: .readOnly, current: []), .refuse(.readOnly))
    }

    func testNotNDEFTagIsRefused() {
        XCTAssertEqual(decide(status: .notSupported, current: []), .refuse(.notNDEFCompatible))
    }

    func testRealCapacityIsChecked() {
        XCTAssertEqual(decide(capacity: 20, current: []), .refuse(.insufficientCapacity(maxMessageLength: 20)))
    }

    // MARK: 2e passage

    func testSecondPassWritesWhenContentUnchanged() throws {
        let current = try NDEFCodec.decode(Fixtures.smartVisionMessage)
        XCTAssertEqual(decide(current: current, expected: current), .write)
    }

    func testSecondPassRefusesAnotherTag() throws {
        let seen = try NDEFCodec.decode(Fixtures.smartVisionMessage)
        XCTAssertEqual(decide(current: [Fixtures.mediaText("Autre")], expected: seen), .refuse(.differentTag))
        XCTAssertEqual(decide(current: [], expected: seen), .refuse(.differentTag))
    }

    func testSecondPassStillRefusesReadOnly() throws {
        let seen = try NDEFCodec.decode(Fixtures.smartVisionMessage)
        XCTAssertEqual(decide(status: .readOnly, current: seen, expected: seen), .refuse(.readOnly))
    }

    // MARK: Relecture

    func testVerification() {
        XCTAssertTrue(WritePlanner.isVerified(readBack: desired, desired: desired))
        XCTAssertTrue(WritePlanner.isVerified(readBack: [Fixtures.mediaText("Banque")], desired: desired))
        XCTAssertFalse(WritePlanner.isVerified(readBack: [], desired: desired))
        XCTAssertFalse(WritePlanner.isVerified(readBack: [Fixtures.mediaText("Banqu")], desired: desired))
    }
}

final class WritePhrasesTests: XCTestCase {
    func testAskReplace() throws {
        let existing = TagDecoder.decode(try NDEFCodec.decode(Fixtures.smartVisionMessage))
        XCTAssertEqual(
            Phrases.askReplace(existing: existing, newName: "Banque"),
            "Cette étiquette contient déjà : Dossier panneau solaire. Voulez-vous la remplacer par : Banque ?"
        )
    }

    func testNameTooLong() {
        let check = CapacityCheck(folderName: String(repeating: "a", count: 113))
        XCTAssertEqual(Phrases.nameTooLong(check),
                       "Ce nom est trop long pour une étiquette. Raccourcissez-le d'environ 3 lettres.")
    }
}
