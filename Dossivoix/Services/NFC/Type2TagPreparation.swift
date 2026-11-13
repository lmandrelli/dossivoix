@preconcurrency import CoreNFC
import DossivoixCore

/// Repli additif : inspecter une structure Type 2 lorsque CoreNFC ne voit pas de NDEF.
/// Il n'écrit jamais le texte utilisateur, ni les verrous, ni la configuration.
@MainActor
enum Type2TagPreparation {
    struct Snapshot {
        let layout: Type2NDEFLayout
        let originalCC: Data
        let preparedCC: Data
    }

    static func inspect(_ tag: NFCTag, ensureCurrent: () throws -> Void) async throws -> Snapshot {
        guard case .miFare(let mifare) = tag, mifare.mifareFamily == .ultralight else {
            throw TagError.notNDEFCompatible
        }
        return try await inspect(send: { try await mifare.sendMiFareCommand(commandPacket: $0) }, ensureCurrent: ensureCurrent)
    }

    static func inspect(send: (Data) async throws -> Data, ensureCurrent: () throws -> Void) async throws -> Snapshot {
        let originalCC = try await readPage(send, page: 3, ensureCurrent: ensureCurrent)
        let cc: Data
        if originalCC.allSatisfy({ $0 == 0 }) {
            try ensureCurrent()
            let version = try await send(Data([0x60]))
            try ensureCurrent()
            cc = try NTAGCapabilityContainer.forVersion(version)
        } else {
            cc = originalCC
        }
        // Valider le CC avant d'utiliser sa taille comme limite de lecture.
        guard cc.count == 4, cc[0] == 0xE1, cc[1] >> 4 == 1,
              cc[2] > 0, cc[2] <= 0x6D, cc[3] >> 4 == 0 else {
            throw TagError.notNDEFCompatible
        }
        var memory = Data()
        for page in 4..<(4 + Int(cc[2]) * 2) {
            memory.append(try await readPage(send, page: UInt8(page), ensureCurrent: ensureCurrent))
        }
        let layout = try Type2NDEFLayout(capabilityContainer: cc, memory: memory)
        return Snapshot(layout: layout, originalCC: originalCC, preparedCC: cc)
    }

    static func prepare(
        _ tag: NFCTag, snapshot: Snapshot, ensureCurrent: () throws -> Void
    ) async throws {
        guard case .miFare(let mifare) = tag else { throw TagError.notNDEFCompatible }
        try await prepare(snapshot: snapshot, send: { try await mifare.sendMiFareCommand(commandPacket: $0) }, ensureCurrent: ensureCurrent)
    }

    static func prepare(
        snapshot: Snapshot, send: (Data) async throws -> Data, ensureCurrent: () throws -> Void
    ) async throws {
        let writes = try snapshot.layout.initializationWrites()
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
