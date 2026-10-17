import XCTest
@testable import DossivoixCore

final class TagCapacityTests: XCTestCase {
    func testNTAG213MaxMessageLength() {
        XCTAssertEqual(TagCapacity.ntag213MaxMessageLength, 141)
        XCTAssertEqual(TagCapacity.maxMessageLength(userMemory: 496), 491) // NTAG 215 : longueur sur 3 octets
    }

    func testReferenceNameFits() {
        let check = CapacityCheck(folderName: Fixtures.folderName)
        XCTAssertTrue(check.fits)
        XCTAssertEqual(check.messageLength, 54)
        // 141 - 17 (marqueur) - 13 (en-tête + type) - 1 (espace final) = 110
        XCTAssertEqual(check.maxNameBytes, 110)
    }

    func testLimitIsInBytes() {
        XCTAssertTrue(CapacityCheck(folderName: String(repeating: "a", count: 110)).fits)

        let tooLong = CapacityCheck(folderName: String(repeating: "a", count: 111))
        XCTAssertFalse(tooLong.fits)
        XCTAssertEqual(tooLong.excessBytes, 1)

        // 56 « é » = 112 octets UTF-8.
        XCTAssertFalse(CapacityCheck(folderName: String(repeating: "é", count: 56)).fits)
    }

    func testUsesRealTagCapacity() {
        XCTAssertFalse(CapacityCheck(folderName: Fixtures.folderName, maxMessageLength: 50).fits)
    }
}

final class TagDiagnosticTests: XCTestCase {
    func testReportOfReferenceTag() throws {
        let report = TagDiagnostic.report(for: try NDEFCodec.decode(Fixtures.smartVisionMessage))

        XCTAssertTrue(report.contains("2 enregistrement(s), 54 octets"))
        XCTAssertTrue(report.contains("TNF : 0x02 (Media (type MIME))"))
        XCTAssertTrue(report.contains("Type : « text/plain »"))
        XCTAssertTrue(report.contains("Payload (4 octets) hex : 54 45 58 54"))
        // L'espace final du nom reste visible dans le diagnostic (avant le guillemet fermant).
        XCTAssertTrue(report.contains("Payload UTF-8 : « Dossier panneau solaire  »"))
        XCTAssertTrue(report.contains("Identifiant : (aucun)"))
    }

    func testReportOfBinaryPayload() {
        let record = NDEFRecord(typeNameFormat: .unknown, type: Data(), payload: Data([0xFF, 0x00]))
        let lines = TagDiagnostic.describe(record)

        XCTAssertTrue(lines.contains("Payload (2 octets) hex : FF 00"))
        XCTAssertTrue(lines.contains("Payload UTF-8 : (non décodable en UTF-8)"))
        XCTAssertTrue(lines.contains("Type : (vide)"))
    }

    func testEmptyReport() {
        XCTAssertEqual(TagDiagnostic.report(for: []), "Aucun enregistrement NDEF.")
    }
}
