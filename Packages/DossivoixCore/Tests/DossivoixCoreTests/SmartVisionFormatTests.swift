import XCTest
@testable import DossivoixCore

final class SmartVisionFormatTests: XCTestCase {
    func testEncodesExactlyLikeTheSmartVision() {
        let records = SmartVisionFormat.standard.records(forFolderName: Fixtures.folderName)
        XCTAssertEqual(NDEFCodec.encode(records), Fixtures.smartVisionMessage)
    }

    func testDoesNotDoubleTrailingSpaceOrInnerSpaces() {
        let records = SmartVisionFormat.standard.records(forFolderName: "  Dossier   panneau solaire ")
        XCTAssertEqual(NDEFCodec.encode(records), Fixtures.smartVisionMessage)
    }

    func testWithoutMarker() {
        let format = SmartVisionFormat(writesMarker: false, appendsTrailingSpace: true)
        XCTAssertEqual(format.records(forFolderName: "Banque"), [Fixtures.mediaText("Banque ")])
    }

    func testWithoutTrailingSpace() {
        let format = SmartVisionFormat(writesMarker: true, appendsTrailingSpace: false)
        XCTAssertEqual(format.records(forFolderName: "Banque"),
                       [Fixtures.mediaText("TEXT"), Fixtures.mediaText("Banque")])
    }

    func testMessageLength() {
        XCTAssertEqual(SmartVisionFormat.standard.messageLength(forFolderName: Fixtures.folderName), 54)
    }

    func testEncodedNameDecodesBack() throws {
        let name = FolderName.preparedForWriting("impôts et taxes 2024")
        let data = NDEFCodec.encode(SmartVisionFormat.standard.records(forFolderName: name))
        let decoded = TagDecoder.decode(try NDEFCodec.decode(data))
        XCTAssertEqual(decoded.outcome, .folderName("Impôts et taxes 2024"))
    }
}

final class FolderNameTests: XCTestCase {
    func testCleaned() {
        XCTAssertEqual(FolderName.cleaned("  Factures \n  2023  "), "Factures 2023")
        XCTAssertEqual(FolderName.cleaned("   "), "")
    }

    func testCleanedKeepsCase() {
        XCTAssertEqual(FolderName.cleaned("dossier EDF"), "dossier EDF")
    }

    func testPreparedForWritingCapitalizesFirstLetterOnly() {
        XCTAssertEqual(FolderName.preparedForWriting("dossier panneau solaire"), "Dossier panneau solaire")
        XCTAssertEqual(FolderName.preparedForWriting("  électricité EDF "), "Électricité EDF")
        XCTAssertEqual(FolderName.preparedForWriting("2023 impôts"), "2023 impôts")
        XCTAssertEqual(FolderName.preparedForWriting(""), "")
    }
}
