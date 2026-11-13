import XCTest
@testable import DossivoixCore

final class BlankNTAGTests: XCTestCase {
    private func model(_ size: UInt8 = 0x0F) throws -> BlankNTAG {
        try BlankNTAG(version: Data([0, 4, 4, 2, 1, 0, size, 3]))
    }

    func testKnownModelsAndBlankMemory() throws {
        for (code, count, cc) in [(UInt8(0x0F), 144, UInt8(0x12)), (0x11, 504, 0x3E), (0x13, 888, 0x6D)] {
            let tag = try model(code)
            XCTAssertEqual(tag.userByteCount, count)
            XCTAssertEqual(tag.ccSize, cc)
            var memory = Data(repeating: 0, count: count)
            XCTAssertNoThrow(try tag.validateEmpty(userMemory: memory))
            memory.replaceSubrange(0..<4, with: [3, 0, 0xFE, 0])
            XCTAssertNoThrow(try tag.validateEmpty(userMemory: memory))
            memory[count - 1] = 1
            XCTAssertThrowsError(try tag.validateEmpty(userMemory: memory))
            XCTAssertThrowsError(try tag.validateEmpty(userMemory: memory.prefix(16)))
        }
    }

    func testUnknownVersionsAreNeverFormatted() {
        for version in [Data(), Data([0, 4, 4, 2, 1, 0, 0x12, 3]), Data([0, 5, 4, 2, 1, 0, 0x0F, 3]), Data([0, 4, 4, 2, 2, 0, 0x0F, 3])] {
            XCTAssertThrowsError(try BlankNTAG(version: version))
        }
    }

    func testExistingAndMalformedTLVsAreNotEmpty() throws {
        let tag = try model()
        for prefix: [UInt8] in [[3, 1, 0xD0, 0xFE], [0xFD, 0, 0xFE, 0], [3, 0xFF, 0, 0], [0, 3, 0, 0xFE]] {
            var memory = Data(repeating: 0, count: tag.userByteCount)
            memory.replaceSubrange(0..<4, with: prefix)
            XCTAssertThrowsError(try tag.validateEmpty(userMemory: memory))
        }
    }

    func testLocksPasswordsMirrorAndCCAreProtected() throws {
        let tag = try model()
        var header = Data(repeating: 0, count: 16)
        header.replaceSubrange(12..<16, with: tag.capabilityContainer)
        var configuration = Data(repeating: 0, count: 16)
        configuration[3] = 0xFF
        let locks = Data(repeating: 0, count: 16)
        XCTAssertNoThrow(try tag.validateWritable(header: header, configuration: configuration, locks: locks))
        XCTAssertNoThrow(try tag.validateWritable(header: Data(repeating: 0, count: 16), configuration: configuration, locks: locks))
        for index in [10, 11, 12, 13, 14, 15] {
            var changed = header; changed[index] ^= 1
            XCTAssertThrowsError(try tag.validateWritable(header: changed, configuration: configuration, locks: locks))
        }
        for index in 0..<3 {
            var changed = locks; changed[index] = 1
            XCTAssertThrowsError(try tag.validateWritable(header: header, configuration: configuration, locks: changed))
        }
        for (index, value) in [(3, UInt8(4)), (0, 0x40), (0, 0x80)] {
            var changed = configuration; changed[index] = value
            XCTAssertThrowsError(try tag.validateWritable(header: header, configuration: changed, locks: locks))
        }
        XCTAssertThrowsError(try tag.validateWritable(header: Data(), configuration: configuration, locks: locks))
    }

    func testShortAndExtendedTLVKeepSmartVisionRecords() throws {
        for (code, length) in [(UInt8(0x0F), 20), (0x11, 300)] {
            let tag = try model(code)
            let records = SmartVisionFormat.standard.records(forFolderName: String(repeating: "é", count: length / 2))
            let pages = try tag.encodedPages(records: records)
            let message = NDEFCodec.encode(records)
            let headerSize = message.count < 255 ? 2 : 4
            XCTAssertEqual(pages[0], 3)
            XCTAssertEqual(pages.count % 4, 0)
            XCTAssertLessThanOrEqual(pages.count, Int(tag.ccSize) * 8)
            XCTAssertEqual(pages[headerSize + message.count], 0xFE)
            XCTAssertEqual(try NDEFCodec.decode(pages.subdata(in: headerSize..<headerSize + message.count)), records)
            if headerSize == 4 {
                XCTAssertEqual(pages[1], 0xFF)
                XCTAssertEqual(Int(pages[2]) * 256 + Int(pages[3]), message.count)
            } else { XCTAssertEqual(Int(pages[1]), message.count) }
        }
    }

    func testCapacityIncludesTLVAndTerminator() throws {
        for code: UInt8 in [0x0F, 0x11, 0x13] {
            let tag = try model(code)
            let size = Int(tag.ccSize) * 8
            // TNF unknown + untyped short/long record: header = 3/6 bytes.
            let overhead = size < 255 ? 6 : 11
            let fits = [NDEFRecord(typeNameFormat: .unknown, type: Data(), payload: Data(repeating: 1, count: size - overhead))]
            XCTAssertEqual(try tag.encodedPages(records: fits).count, size)
            let tooBig = [NDEFRecord(typeNameFormat: .unknown, type: Data(), payload: Data(repeating: 1, count: size - overhead + 1))]
            XCTAssertThrowsError(try tag.encodedPages(records: tooBig))
        }
    }
}
