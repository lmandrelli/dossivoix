@preconcurrency import CoreNFC
import DossivoixCore

extension CoreNFCTagService {
    /// Ce repli ne s'applique qu'aux NTAG21x que CoreNFC ne reconnaît pas comme NDEF.
    /// La lecture reste strictement sans écriture, y compris sur une puce non formatée.
    static func inspectBlankNTAG(
        _ tag: NFCTag, ensureCurrent: () throws -> Void
    ) async throws -> BlankNTAG {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily == .ultralight else {
            throw TagError.notNDEFCompatible
        }
        try ensureCurrent()
        let version = try await mifare.sendMiFareCommand(commandPacket: Data([0x60]))
        try ensureCurrent()
        let blank = try BlankNTAG(version: version)
        let memory = try await readUserMemory(mifare, count: blank.userByteCount, ensureCurrent: ensureCurrent)
        try blank.validateEmpty(userMemory: memory)
        return blank
    }

    private static func readPages(
        _ tag: NFCMiFareTag, page: UInt8, ensureCurrent: () throws -> Void
    ) async throws -> Data {
        try ensureCurrent()
        let data = try await tag.sendMiFareCommand(commandPacket: Data([0x30, page]))
        try ensureCurrent()
        guard data.count == 16 else { throw TagError.unreadable }
        return data
    }

    private static func readUserMemory(
        _ tag: NFCMiFareTag, count: Int, ensureCurrent: () throws -> Void
    ) async throws -> Data {
        var memory = Data()
        while memory.count < count {
            // FAST_READ refuse une zone protégée, sans le retour au début de mémoire
            // que READ peut effectuer : une protection ne doit pas passer pour du vide.
            let length = min(16, count - memory.count)
            let first = UInt8(4 + memory.count / 4)
            let last = first + UInt8(length / 4) - 1
            try ensureCurrent()
            let bytes = try await tag.sendMiFareCommand(commandPacket: Data([0x3A, first, last]))
            try ensureCurrent()
            guard bytes.count == length else { throw TagError.unreadable }
            memory.append(bytes)
        }
        return memory
    }

    static func writeBlankNTAG(
        _ tag: NFCTag, blank: BlankNTAG, records: [NDEFRecord], ensureCurrent: () throws -> Void
    ) async throws {
        guard case .miFare(let mifare) = tag else { throw TagError.notNDEFCompatible }
        let pages = try blank.encodedPages(records: records)
        let header = try await readPages(mifare, page: 0, ensureCurrent: ensureCurrent)
        let configuration = try await readPages(mifare, page: blank.configurationPage, ensureCurrent: ensureCurrent)
        let locks = try await readPages(mifare, page: blank.lockPage, ensureCurrent: ensureCurrent)
        try blank.validateWritable(header: header, configuration: configuration, locks: locks)

        // Longueur nulle pendant l'écriture ; publier la première page en dernier.
        // Une interruption ne doit jamais être annoncée comme une écriture réussie.
        try await writePage(mifare, page: 4, bytes: Data([3, 0, 0xFE, 0]), ensureCurrent: ensureCurrent)
        for offset in stride(from: 4, to: pages.count, by: 4) {
            try await writePage(mifare, page: UInt8(4 + offset / 4),
                                bytes: pages.subdata(in: offset..<offset + 4), ensureCurrent: ensureCurrent)
        }
        try await writePage(mifare, page: 4, bytes: Data(pages.prefix(4)), ensureCurrent: ensureCurrent)
        if header.suffix(4).allSatisfy({ $0 == 0 }) {
            // CC uniquement s'il est entièrement vierge. Ne jamais modifier ses bits d'accès.
            try await writePage(mifare, page: 3, bytes: blank.capabilityContainer, ensureCurrent: ensureCurrent)
        }
        let readBack = try await readUserMemory(mifare, count: blank.userByteCount, ensureCurrent: ensureCurrent)
        let finalHeader = try await readPages(mifare, page: 0, ensureCurrent: ensureCurrent)
        guard readBack.prefix(pages.count) == pages,
              finalHeader.suffix(4) == blank.capabilityContainer else { throw TagError.writeFailed }
    }

    private static func writePage(
        _ tag: NFCMiFareTag, page: UInt8, bytes: Data, ensureCurrent: () throws -> Void
    ) async throws {
        try ensureCurrent()
        let response = try await tag.sendMiFareCommand(commandPacket: Data([0xA2, page]) + bytes)
        try ensureCurrent()
        guard response == Data([0x0A]) else { throw TagError.writeFailed }
    }
}
