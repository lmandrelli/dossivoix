import XCTest
@testable import DossivoixCore

final class Type2NDEFLayoutTests: XCTestCase {
    private let cc = Data([0xE1, 0x10, 0x12, 0])

    private func memory(_ prefix: [UInt8], count: Int = 144) -> Data {
        Data(prefix + Array(repeating: 0, count: count - prefix.count))
    }

    private func apply(_ writes: [Type2NDEFLayout.PageWrite], to memory: Data) -> Data {
        var result = memory
        for write in writes {
            let offset = (Int(write.page) - 4) * 4
            result.replaceSubrange(offset..<offset + 4, with: write.bytes)
        }
        return result
    }

    func testFactoryLockControlIsEmptyAndPreserved() throws {
        let source = memory([1, 3, 0xA0, 0x0C, 0x34, 3, 0, 0xFE])
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: source)
        XCTAssertTrue(layout.message.isEmpty)
        let initialized = apply(try layout.initializationWrites(), to: source)
        XCTAssertEqual(initialized.prefix(5), source.prefix(5))
        let result = try Type2NDEFLayout(capabilityContainer: cc, memory: initialized)
        XCTAssertEqual(result.message, Data([0xD0, 0, 0]))
        XCTAssertEqual(TagDecoder.decode(try NDEFCodec.decode(result.message)).outcome, .empty)
    }

    func testAllZeroAndNullPaddedAndTerminatorAndEmptyTLV() throws {
        for prefix: [UInt8] in [[], [0xFE], [3, 0, 0xFE], [0, 0, 0, 3, 0, 0xFE], [3, 0xFF, 0, 0, 0xFE]] {
            let source = memory(prefix)
            let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: source)
            XCTAssertTrue(layout.message.isEmpty)
            let initialized = apply(try layout.initializationWrites(), to: source)
            XCTAssertEqual(try Type2NDEFLayout(capabilityContainer: cc, memory: initialized).message, Data([0xD0, 0, 0]))
        }
    }

    func testNoRevisionOrAntennaRestrictionWhenCCMissing() throws {
        for (size, ccSize): (UInt8, UInt8) in [(0x0F, 0x12), (0x11, 0x3E), (0x13, 0x6D)] {
            for subtype: UInt8 in [1, 2] {
                for revision: UInt8 in [0, 1, 2] {
                    let version = Data([0, 4, 4, subtype, 1, revision, size, 3])
                    XCTAssertEqual(try NTAGCapabilityContainer.forVersion(version), Data([0xE1, 0x10, ccSize, 0]))
                }
            }
        }
        XCTAssertThrowsError(try NTAGCapabilityContainer.forVersion(Data([0, 5, 4, 2, 1, 0, 0x11, 3])))
        XCTAssertThrowsError(try NTAGCapabilityContainer.forVersion(Data([0, 4, 4])))
    }

    func testExistingNDEFIsReadExactlyAndNeverInitialized() throws {
        let records = SmartVisionFormat.standard.records(forFolderName: "Factures")
        let encoded = NDEFCodec.encode(records)
        let source = memory([3, UInt8(encoded.count)] + encoded + [0xFE])
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: source)
        XCTAssertEqual(try NDEFCodec.decode(layout.message), records)
        XCTAssertThrowsError(try layout.initializationWrites())
    }

    func testNonzeroTailAfterTerminatorIsNotMistakenForContentOrErased() throws {
        var source = memory([3, 0, 0xFE])
        source[100] = 0x42
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: source)
        XCTAssertTrue(layout.message.isEmpty)
        let result = apply(try layout.initializationWrites(), to: source)
        XCTAssertEqual(result[100], 0x42)
    }

    func testImmediateResidualDataIsNotOverwrittenDuringInitialization() throws {
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: memory([3, 0, 0xFE, 0x42]))
        XCTAssertTrue(layout.message.isEmpty)
        XCTAssertThrowsError(try layout.initializationWrites())
    }

    func testReadOnlyCanBeReadButNotInitialized() throws {
        let layout = try Type2NDEFLayout(capabilityContainer: Data([0xE1, 0x10, 0x12, 0x0F]), memory: memory([3, 0, 0xFE]))
        XCTAssertTrue(layout.message.isEmpty)
        XCTAssertThrowsError(try layout.initializationWrites()) { XCTAssertEqual($0 as? TagError, .readOnly) }
    }

    func testMalformedTLVAndUnknownContentAreNotBlank() {
        for prefix: [UInt8] in [[3, 0xFF, 1, 0], [1, 2, 0, 0], [0xFD, 0, 0xFE], [3, 200]] {
            XCTAssertThrowsError(try Type2NDEFLayout(capabilityContainer: cc, memory: memory(prefix)))
        }
        XCTAssertThrowsError(try Type2NDEFLayout(capabilityContainer: cc, memory: Data()))
        XCTAssertThrowsError(try Type2NDEFLayout(capabilityContainer: Data(repeating: 0, count: 4), memory: memory([])))
    }

    func testMemoryControlIsPreservedAndReservedBytesAreNeverWritten() throws {
        let safe = memory([2, 3, 0xA0, 4, 4, 3, 0, 0xFE])
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: safe)
        XCTAssertEqual(apply(try layout.initializationWrites(), to: safe).prefix(5), safe.prefix(5))
        // Réservation à l'octet physique 24, dans les pages à initialiser.
        let unsafe = memory([2, 3, 0x60, 4, 2, 3, 0, 0xFE])
        XCTAssertThrowsError(try Type2NDEFLayout(capabilityContainer: cc, memory: unsafe).initializationWrites())
    }

    func testLengthPageIsPublishedLastEvenAcrossPageBoundary() throws {
        let source = memory([0, 0, 0, 3, 0, 0xFE])
        let writes = try Type2NDEFLayout(capabilityContainer: cc, memory: source).initializationWrites()
        XCTAssertEqual(writes.last?.page, 5)
    }

    func testLarge215MessageAndCapacityAreDelegatedToNativeWriter() throws {
        let cc215 = Data([0xE1, 0x10, 0x3E, 0])
        let layout = try Type2NDEFLayout(capabilityContainer: cc215, memory: memory([], count: 496))
        XCTAssertNoThrow(try layout.checkCapacity(for: SmartVisionFormat.standard.records(forFolderName: String(repeating: "a", count: 300))))
        XCTAssertThrowsError(try layout.checkCapacity(for: SmartVisionFormat.standard.records(forFolderName: String(repeating: "a", count: 600))))
        XCTAssertLessThanOrEqual(try layout.initializationWrites().count, 2)
    }
    func testPreparationIsIdempotent() throws {
        let source = memory([3, 3, 0xD0, 0, 0, 0xFE])
        XCTAssertEqual(try Type2NDEFLayout(capabilityContainer: cc, memory: source).initializationWrites(), [])
    }

    func testEveryInterruptedPreparationCanBeRetriedWithoutMovingTheTLV() throws {
        for prefix: [UInt8] in [[], [1, 3, 0xA0, 0x0C, 0x34, 3, 0, 0xFE], [0, 0, 0, 3, 0, 0xFE]] {
            let source = memory(prefix)
            let writes = try Type2NDEFLayout(capabilityContainer: cc, memory: source).initializationWrites()
            let expected = apply(writes, to: source)
            for completed in 0...writes.count {
                let interrupted = apply(Array(writes.prefix(completed)), to: source)
                let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: interrupted)
                XCTAssertTrue(layout.message.isEmpty || layout.message == Data([0xD0, 0, 0]))
                XCTAssertEqual(apply(try layout.initializationWrites(), to: interrupted), expected)
            }
        }
    }

    func test216AndNoSpaceAtEnd() throws {
        let largeCC = Data([0xE1, 0x10, 0x6D, 0])
        XCTAssertNoThrow(try Type2NDEFLayout(capabilityContainer: largeCC, memory: memory([], count: 872)).initializationWrites())
        var full = memory([])
        full.replaceSubrange(142..<144, with: [3, 0])
        XCTAssertThrowsError(try Type2NDEFLayout(capabilityContainer: cc, memory: full).initializationWrites())
    }

}
