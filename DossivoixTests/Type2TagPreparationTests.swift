import XCTest
import DossivoixCore
@testable import Dossivoix

@MainActor
final class Type2TagPreparationTests: XCTestCase {
    private final class Chip {
        var memory = Data(repeating: 0, count: 540)
        var commands: [Data] = []
        var ignoreWrites = false
        var readOnly = false
        let cc = Data([0xE1, 0x10, 0x3E, 0])

        func send(_ command: Data) async throws -> Data {
            commands.append(command)
            switch command[0] {
            case 0x60: return Data([0, 4, 4, 1, 2, 1, 0x11, 3])
            case 0x30:
                let start = Int(command[1]) * 4
                return memory.subdata(in: start..<start + 16)
            case 0xA2:
                if readOnly { throw TagError.readOnly }
                let start = Int(command[1]) * 4
                if !ignoreWrites { memory.replaceSubrange(start..<start + 4, with: command.dropFirst(2)) }
                return Data() // L'ACK peut ne pas être représenté par un octet 0A.
            default: throw TagError.unreadable
            }
        }
        var writePages: [UInt8] { commands.filter { $0[0] == 0xA2 }.map { $0[1] } }
    }

    func testReadOfUnformattedTagNeverWritesAndPreparationWritesCCLast() async throws {
        let chip = Chip()
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        XCTAssertTrue(snapshot.layout.message.isEmpty)
        XCTAssertTrue(chip.writePages.isEmpty)
        try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: {})
        XCTAssertEqual(chip.writePages, [5, 4, 3])
        XCTAssertEqual(chip.memory.subdata(in: 12..<16), chip.cc)
        XCTAssertEqual(chip.memory.subdata(in: 16..<22), Data([3, 3, 0xD0, 0, 0, 0xFE]))
        XCTAssertTrue(chip.memory.suffix(20).allSatisfy { $0 == 0 })
    }

    func testValidCCNeverQueriesVersionOrRewritesCC() async throws {
        let chip = Chip()
        chip.memory.replaceSubrange(12..<16, with: chip.cc)
        chip.memory.replaceSubrange(16..<24, with: [1, 3, 0xA0, 0x0C, 0x34, 3, 0, 0xFE])
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        XCTAssertFalse(chip.commands.contains { $0[0] == 0x60 })
        try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: {})
        XCTAssertFalse(chip.writePages.contains(3))
        XCTAssertEqual(chip.memory.subdata(in: 16..<21), Data([1, 3, 0xA0, 0x0C, 0x34]))
        let again = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        let count = chip.writePages.count
        try await Type2TagPreparation.prepare(snapshot: again, send: chip.send, ensureCurrent: {})
        XCTAssertEqual(chip.writePages.count, count)
    }

    func testReadBackFailureIsNotReportedAsSuccess() async throws {
        let chip = Chip()
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        chip.ignoreWrites = true
        do {
            try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: {})
            XCTFail("La relecture doit détecter une écriture sans effet")
        } catch { XCTAssertEqual(error as? TagError, .writeFailed) }
        XCTAssertFalse(chip.writePages.contains(3))
    }

    func testCancellationPreventsAnyWrite() async throws {
        let chip = Chip()
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        do {
            try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: { throw TagError.userCanceled })
            XCTFail("Session annulée")
        } catch { XCTAssertEqual(error as? TagError, .userCanceled) }
        XCTAssertTrue(chip.writePages.isEmpty)
    }

    func testChangedCCIsNeverOverwritten() async throws {
        let chip = Chip()
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        chip.memory[12] = 1
        do {
            try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: {})
            XCTFail("Un CC non nul ne doit jamais être modifié")
        } catch { XCTAssertEqual(error as? TagError, .writeFailed) }
        XCTAssertFalse(chip.writePages.contains(3))
        XCTAssertEqual(chip.memory[12], 1)
    }

    func testWriteProtectionErrorIsPropagatedWithoutWritingCC() async throws {
        let chip = Chip()
        let snapshot = try await Type2TagPreparation.inspect(send: chip.send, ensureCurrent: {})
        chip.readOnly = true
        do {
            try await Type2TagPreparation.prepare(snapshot: snapshot, send: chip.send, ensureCurrent: {})
            XCTFail("Une protection matérielle ne doit pas être ignorée")
        } catch { XCTAssertEqual(error as? TagError, .readOnly) }
        XCTAssertFalse(chip.writePages.contains(3))
    }
}
