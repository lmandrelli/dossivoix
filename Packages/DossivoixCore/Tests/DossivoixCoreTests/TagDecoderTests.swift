import XCTest
@testable import DossivoixCore

final class TagDecoderTests: XCTestCase {
    func testReadsSmartVisionTag() throws {
        let decoded = TagDecoder.decode(try NDEFCodec.decode(Fixtures.smartVisionMessage))

        XCTAssertEqual(decoded.outcome, .folderName("Dossier panneau solaire"))
        XCTAssertEqual(decoded.folderName, "Dossier panneau solaire")
        XCTAssertFalse(decoded.hasUnrecognizedParts)
    }

    func testTextWithoutMarker() {
        let decoded = TagDecoder.decode([Fixtures.mediaText("  Factures   2023 ")])
        XCTAssertEqual(decoded.outcome, .folderName("Factures 2023"))
    }

    func testWellKnownTextUTF8() {
        let decoded = TagDecoder.decode([Fixtures.wellKnownText("Impôts 2024", language: "fr-FR")])
        XCTAssertEqual(decoded.outcome, .folderName("Impôts 2024"))
    }

    func testWellKnownTextUTF16BigEndian() {
        var payload = Data([0x80 | 2]) + Data("fr".utf8)
        payload += "Santé".data(using: .utf16BigEndian)!
        let record = NDEFRecord(typeNameFormat: .wellKnown, type: Data("T".utf8), payload: payload)
        XCTAssertEqual(TagDecoder.decode([record]).outcome, .folderName("Santé"))
    }

    func testMarkerFollowedByWellKnownText() {
        let decoded = TagDecoder.decode([Fixtures.mediaText("TEXT"), Fixtures.wellKnownText("Banque")])
        XCTAssertEqual(decoded.outcome, .folderName("Banque"))
    }

    func testMIMETypeIsCaseInsensitiveWithParameters() {
        let record = NDEFRecord(typeNameFormat: .media, type: Data("Text/Plain; charset=utf-8".utf8),
                                payload: Data("Assurance".utf8))
        XCTAssertEqual(TagDecoder.decode([record]).outcome, .folderName("Assurance"))
    }

    func testSeveralTextsAreJoined() {
        let decoded = TagDecoder.decode([
            Fixtures.mediaText("TEXT"), Fixtures.mediaText("Maison "), Fixtures.mediaText("Travaux"),
        ])
        XCTAssertEqual(decoded.outcome, .folderName("Maison, Travaux"))
    }

    func testLoneTextRecordIsANameEvenIfItReadsTEXT() {
        XCTAssertEqual(TagDecoder.decode([Fixtures.mediaText("TEXT")]).outcome, .folderName("TEXT"))
    }

    func testEmptyTag() {
        XCTAssertEqual(TagDecoder.decode([]).outcome, .empty)
        let emptyRecord = NDEFRecord(typeNameFormat: .empty, type: Data(), payload: Data())
        XCTAssertEqual(TagDecoder.decode([emptyRecord]).outcome, .empty)
        XCTAssertEqual(TagDecoder.decode([Fixtures.mediaText("   ")]).outcome, .empty)
    }

    func testMarkerFollowedByBlankTextIsUnrecognized() {
        let decoded = TagDecoder.decode([Fixtures.mediaText("TEXT"), Fixtures.mediaText(" ")])
        XCTAssertEqual(decoded.outcome, .unrecognized)
    }

    func testURIRecordIsUnrecognized() {
        let uri = NDEFRecord(typeNameFormat: .wellKnown, type: Data("U".utf8),
                             payload: Data([0x04]) + Data("example.com".utf8))
        let decoded = TagDecoder.decode([uri])

        XCTAssertEqual(decoded.outcome, .unrecognized)
        XCTAssertEqual(decoded.unrecognizedRecords, [uri])
    }

    func testMarkerFollowedByUnknownMIMEIsUnrecognized() {
        let audio = NDEFRecord(typeNameFormat: .media, type: Data("audio/amr".utf8), payload: Data([1, 2, 3]))
        let decoded = TagDecoder.decode([Fixtures.mediaText("TEXT"), audio])

        XCTAssertEqual(decoded.outcome, .unrecognized)
        XCTAssertEqual(decoded.unrecognizedRecords, [audio])
    }

    func testNameWithUnrecognizedPartIsFlagged() {
        let external = NDEFRecord(typeNameFormat: .external, type: Data("kapsys.com:v".utf8), payload: Data([9]))
        let decoded = TagDecoder.decode([Fixtures.mediaText("TEXT"), Fixtures.mediaText("Banque "), external])

        XCTAssertEqual(decoded.outcome, .folderName("Banque"))
        XCTAssertTrue(decoded.hasUnrecognizedParts)
    }

    func testInvalidUTF8IsUnrecognized() {
        let record = NDEFRecord(typeNameFormat: .media, type: Fixtures.textPlain, payload: Data([0xC3, 0x28]))
        XCTAssertEqual(TagDecoder.decode([record]).outcome, .unrecognized)
    }
}
