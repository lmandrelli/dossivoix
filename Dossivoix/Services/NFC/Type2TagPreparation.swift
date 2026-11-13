@preconcurrency import CoreNFC
import DossivoixCore

/// Repli additif : inspecter une structure Type 2 lorsque CoreNFC ne voit pas de NDEF.
/// Il n'écrit jamais le texte utilisateur, ni les verrous, ni la configuration.
@MainActor
enum Type2TagPreparation {
    struct Snapshot {
        let layout: Type2TagContents
        let originalCC: Data
        let preparedCC: Data
    }

    static func inspect(_ tag: NFCTag, ensureCurrent: () throws -> Void, diagnostic: (String) -> Void = { _ in }) async throws -> Snapshot {
        switch tag {
        case .miFare(let m):
            diagnostic("UID : " + m.identifier.map { String(format: "%02X", $0) }.joined())
            diagnostic("Famille MIFARE : \(m.mifareFamily.rawValue)")
        case .iso7816: diagnostic("Type : iso7816")
        case .iso15693: diagnostic("Type : iso15693")
        case .feliCa: diagnostic("Type : felica")
        @unknown default: diagnostic("Type : unknown")
        }
        guard case .miFare(let mifare) = tag, (mifare.mifareFamily == .ultralight || mifare.mifareFamily == .unknown) else {
            throw TagError.notNDEFCompatible
        }
        return try await inspect(send: { try await mifare.sendMiFareCommand(commandPacket: $0) }, ensureCurrent: ensureCurrent, diagnostic: diagnostic)
    }

    static func inspect(send: (Data) async throws -> Data, ensureCurrent: () throws -> Void, diagnostic: (String) -> Void = { _ in }) async throws -> Snapshot {
        let originalCC = try await readPage(send, page: 3, ensureCurrent: ensureCurrent)
        diagnostic("CC : " + originalCC.map { String(format: "%02X", $0) }.joined(separator: " "))
        let cc: Data
        if originalCC.allSatisfy({ $0 == 0 }) {
            try ensureCurrent()
            let version = try await send(Data([0x60]))
            try ensureCurrent()
            diagnostic("GET_VERSION : " + version.map { String(format: "%02X", $0) }.joined(separator: " "))
            cc = try NTAGCapabilityContainer.forVersion(version)
        } else {
            cc = originalCC
        }
        // Valider le CC avant d'utiliser sa taille comme limite de lecture.
        guard cc.count == 4, cc[0] == 0xE1, cc[1] >> 4 == 1,
              cc[2] > 0, cc[2] <= 0x7E, cc[3] >> 4 == 0 else {
            throw TagError.notNDEFCompatible
        }
        var memory = Data()
        for page in 4..<(4 + Int(cc[2]) * 2) {
            memory.append(try await readPage(send, page: UInt8(page), ensureCurrent: ensureCurrent))
            if memory.count >= 8, (try? Type2TagContents(capabilityContainer: cc, memory: memory)) != nil { break }
        }
        diagnostic("Mémoire utilisateur lue : \(memory.count)/\(Int(cc[2]) * 8) octets, \(memory.filter { $0 != 0 }.count) non nuls")
        for offset in stride(from: 0, to: memory.count, by: 16) {
            let bytes = memory.subdata(in: offset..<min(offset + 16, memory.count))
            diagnostic(String(format: "Page %02X : ", 4 + offset / 4) + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        let layout = try Type2TagContents(capabilityContainer: cc, memory: memory)
        diagnostic("Enregistrements NDEF actifs : \(layout.records.count)")
        return Snapshot(layout: layout, originalCC: originalCC, preparedCC: cc)
    }

    static func prepare(
        _ tag: NFCTag, snapshot: Snapshot, replacingExisting: Bool = false, ensureCurrent: () throws -> Void
    ) async throws {
        guard case .miFare(let mifare) = tag else { throw TagError.notNDEFCompatible }
        try await prepare(snapshot: snapshot, replacingExisting: replacingExisting, send: { try await mifare.sendMiFareCommand(commandPacket: $0) }, ensureCurrent: ensureCurrent)
    }

    static func prepare(
        snapshot: Snapshot, replacingExisting: Bool = false, send: (Data) async throws -> Data, ensureCurrent: () throws -> Void
    ) async throws {
        let writes = try snapshot.layout.initializationWrites(replacingExisting: replacingExisting)
        for write in writes {
            try await writeAndVerify(send, page: write.page, bytes: write.bytes, ensureCurrent: ensureCurrent)
        }
        if snapshot.originalCC != snapshot.preparedCC {
            // La page CC est OTP : ne l'initialiser que si elle est encore entièrement nulle.
            let currentCC = try await readPage(send, page: 3, ensureCurrent: ensureCurrent)
            guard currentCC == Data(repeating: 0, count: 4) else { throw TagError.writeFailed }
            try await writeAndVerify(send, page: 3, bytes: snapshot.preparedCC, ensureCurrent: ensureCurrent)
        }
    }

    static func clear(_ tag: NFCTag, snapshot: Snapshot, ensureCurrent: () throws -> Void) async throws {
        guard case .miFare(let mifare) = tag else { throw TagError.notNDEFCompatible }
        try await clear(snapshot: snapshot, send: { try await mifare.sendMiFareCommand(commandPacket: $0) }, ensureCurrent: ensureCurrent)
    }

    static func clear(snapshot: Snapshot, send: (Data) async throws -> Data, ensureCurrent: () throws -> Void) async throws {
        for write in try snapshot.layout.clearingWrites() {
            try await writeAndVerify(send, page: write.page, bytes: write.bytes, ensureCurrent: ensureCurrent)
        }
        if snapshot.originalCC != snapshot.preparedCC {
            guard try await readPage(send, page: 3, ensureCurrent: ensureCurrent) == Data(repeating: 0, count: 4) else {
                throw TagError.writeFailed
            }
            try await writeAndVerify(send, page: 3, bytes: snapshot.preparedCC, ensureCurrent: ensureCurrent)
        }
        let checked = try await inspect(send: send, ensureCurrent: ensureCurrent)
        guard checked.layout.records.isEmpty else { throw TagError.writeFailed }
    }

    private static func readPage(
        _ send: (Data) async throws -> Data, page: UInt8, ensureCurrent: () throws -> Void
    ) async throws -> Data {
        try ensureCurrent()
        let bytes = try await send(Data([0x30, page]))
        try ensureCurrent()
        guard bytes.count == 16 else { throw TagError.unreadable }
        // READ renvoie 4 pages, mais peut boucler devant une zone protégée.
        // Seule la première page (adresse effectivement demandée) est utilisée.
        return Data(bytes.prefix(4))
    }

    private static func writeAndVerify(
        _ send: (Data) async throws -> Data, page: UInt8, bytes: Data, ensureCurrent: () throws -> Void
    ) async throws {
        try ensureCurrent()
        // Pas d'hypothèse sur l'encapsulation de l'ACK 4 bits par CoreNFC.
        _ = try await send(Data([0xA2, page]) + bytes)
        try ensureCurrent()
        let readBack = try await readPage(send, page: page, ensureCurrent: ensureCurrent)
        guard readBack == bytes else { throw TagError.writeFailed }
    }
}
