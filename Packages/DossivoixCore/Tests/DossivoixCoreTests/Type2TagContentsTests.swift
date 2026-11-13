import XCTest
@testable import DossivoixCore

final class Type2TagContentsTests: XCTestCase {
    private let cc = Data([0xE1, 0x10, 0x3E, 0])
    private func padded(_ bytes: Data) -> Data {
        bytes + Data(repeating: 0, count: 496 - bytes.count)
    }

    func testNoNDEFMeansEmptyEvenWhenRawMemoryResemblesAnOldMessage() throws {
        // Structure observée : données brutes, mais aucune encapsulation NDEF active.
        // Utiliser du texte synthétique, jamais le relevé personnel de l'utilisateur.
        let old = SmartVisionFormat.standard.records(forFolderName: String(repeating: "a", count: 381))
        let message = NDEFCodec.encode(old)
        let memory = padded(Data(message.prefix(4)) + message + Data([0xFE]))
        let content = try Type2TagContents(capabilityContainer: cc, memory: memory)
        XCTAssertEqual(content.records, [])
        XCTAssertEqual(TagDecoder.decode(content.records).outcome, .empty)
        XCTAssertNoThrow(try content.initializationWrites())
        let desired = SmartVisionFormat.standard.records(forFolderName: "Nouveau dossier")
        XCTAssertEqual(WritePlanner.decide(status: .readWrite, capacity: content.maxMessageLength,
                                           current: content.records, desired: desired, expectedCurrent: nil), .write)
    }

    func testRawBytesWithoutNDEFDoNotBecomeUserContent() throws {
        for raw in [Data([0x92, 0xFF, 0xFF, 7]), Data(repeating: 0xFF, count: 400)] {
            let content = try Type2TagContents(capabilityContainer: cc, memory: padded(raw))
            XCTAssertEqual(content.records, [])
            XCTAssertNoThrow(try content.initializationWrites())
        }
    }

    func testTrulyBlankAndFactoryBlankRemainEmpty() throws {
        for prefix in [Data(), Data([3, 0, 0xFE]), Data([1, 3, 0xA0, 0x0C, 0x34, 3, 0, 0xFE])] {
            let content = try Type2TagContents(capabilityContainer: cc, memory: padded(prefix))
            XCTAssertEqual(TagDecoder.decode(content.records).outcome, .empty)
            XCTAssertNoThrow(try content.initializationWrites())
        }
    }

    func testExistingActiveNDEFRetainsTextAndReplaceConfirmation() throws {
        let records = SmartVisionFormat.standard.records(forFolderName: "Banque")
        let message = NDEFCodec.encode(records)
        let control = Data([1, 3, 0xA0, 0x0C, 0x34])
        var memory = padded(control + Data([3, UInt8(message.count)]) + message + Data([0xFE]))
        let content = try Type2TagContents(capabilityContainer: cc, memory: memory)
        XCTAssertEqual(content.records, records)
        let desired = SmartVisionFormat.standard.records(forFolderName: "Autre dossier")
        guard case .askReplace = WritePlanner.decide(status: .readWrite, capacity: content.maxMessageLength,
                                                    current: content.records, desired: desired, expectedCurrent: nil) else {
            return XCTFail("Les données NDEF actives doivent garder la confirmation")
        }
        XCTAssertThrowsError(try content.initializationWrites())
        for write in try content.initializationWrites(replacingExisting: true) {
            let start = (Int(write.page) - 4) * 4
            memory.replaceSubrange(start..<start + 4, with: write.bytes)
        }
        XCTAssertEqual(memory.prefix(5), control)
        XCTAssertEqual(TagDecoder.decode(try Type2TagContents(capabilityContainer: cc, memory: memory).records).outcome, .empty)
    }

    func testMalformedActiveNDEFPayloadIsNotDeclaredEmpty() throws {
        let content = try Type2TagContents(capabilityContainer: cc, memory: padded(Data([3, 3, 0xD2, 10, 200, 0xFE])))
        XCTAssertEqual(TagDecoder.decode(content.records).outcome, .unrecognized)
    }

    func testLargerType2CapacityIsNotFilteredByNTAGModel() throws {
        let content = try Type2TagContents(capabilityContainer: Data([0xE1, 0x10, 0x7E, 0]), memory: Data(repeating: 0, count: 1008))
        XCTAssertEqual(content.capacity, 1008)
        XCTAssertEqual(content.records, [])
    }
}
