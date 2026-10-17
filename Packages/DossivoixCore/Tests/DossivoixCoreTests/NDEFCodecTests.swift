import XCTest
@testable import DossivoixCore

final class NDEFCodecTests: XCTestCase {
    func testReferenceMessageIs54Bytes() {
        XCTAssertEqual(Fixtures.smartVisionMessage.count, 54)
    }

    func testDecodesReferenceMessage() throws {
        let records = try NDEFCodec.decode(Fixtures.smartVisionMessage)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0], Fixtures.mediaText("TEXT"))
        XCTAssertEqual(records[1], Fixtures.mediaText("Dossier panneau solaire "))
        XCTAssertTrue(records.allSatisfy { $0.identifier.isEmpty })
    }

    func testEncodeDecodeRoundTrip() throws {
        let records = [
            Fixtures.mediaText("TEXT"),
            NDEFRecord(typeNameFormat: .external, type: Data("kapsys.com:x".utf8),
                       identifier: Data("id".utf8), payload: Data([0x00, 0xFF])),
            Fixtures.wellKnownText("Impôts 2024"),
        ]
        XCTAssertEqual(try NDEFCodec.decode(NDEFCodec.encode(records)), records)
    }

    func testLongRecordUsesFourByteLength() throws {
        let record = Fixtures.mediaText(String(repeating: "a", count: 300))
        let data = NDEFCodec.encode([record])

        XCTAssertEqual(data[0] & 0x10, 0, "SR ne doit pas être positionné")
        XCTAssertEqual(Array(data[2..<6]), [0x00, 0x00, 0x01, 0x2C])
        XCTAssertEqual(try NDEFCodec.decode(data), [record])
    }

    func testTruncatedDataThrows() {
        let truncated = Fixtures.smartVisionMessage.prefix(40)
        XCTAssertThrowsError(try NDEFCodec.decode(truncated)) { error in
            guard case NDEFCodecError.truncated = error else {
                return XCTFail("Erreur inattendue : \(error)")
            }
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try NDEFCodec.decode(Data())) { error in
            XCTAssertEqual(error as? NDEFCodecError, .emptyData)
        }
    }

    func testChunkedRecordThrows() {
        // En-tête avec le bit CF (0x20).
        let data = Data([0xB2, 0x0A, 0x01]) + Fixtures.textPlain + Data([0x41])
        XCTAssertThrowsError(try NDEFCodec.decode(data)) { error in
            XCTAssertEqual(error as? NDEFCodecError, .chunkedRecordNotSupported)
        }
    }

    func testIgnoresBytesAfterMessageEnd() throws {
        // Terminateur TLV 0xFE et octets nuls après le message.
        let data = Fixtures.smartVisionMessage + Data([0xFE, 0x00, 0x00])
        XCTAssertEqual(try NDEFCodec.decode(data).count, 2)
    }

    func testHexHelpers() {
        XCTAssertEqual(Data(hexString: "92:0a-04")?.hexString, "92 0A 04")
        XCTAssertNil(Data(hexString: "9"))
        XCTAssertNil(Data(hexString: "ZZ"))
    }
}
