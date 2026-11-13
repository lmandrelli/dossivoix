import Foundation

/// Initialisation conservatrice des NTAG213/215/216 sans message NDEF.
/// Référence : NXP NTAG213_215_216, sections 8.5, 8.8 et 10.1.
public struct BlankNTAG: Sendable {
    public let userByteCount: Int
    public let ccSize: UInt8
    public var lockPage: UInt8 { UInt8(4 + userByteCount / 4) }
    public var configurationPage: UInt8 { lockPage + 1 }
    public var capabilityContainer: Data { Data([0xE1, 0x10, ccSize, 0]) }

    public init(version: Data) throws {
        let bytes = Array(version)
        guard bytes.count == 8,
              Array(bytes[0..<6]) == [0, 4, 4, 2, 1, 0], bytes[7] == 3 else {
            throw TagError.notNDEFCompatible
        }
        switch bytes[6] {
        case 0x0F: userByteCount = 144; ccSize = 0x12
        case 0x11: userByteCount = 504; ccSize = 0x3E
        case 0x13: userByteCount = 888; ccSize = 0x6D
        default: throw TagError.notNDEFCompatible
        }
    }

    /// Ne considère jamais un contenu inconnu comme vide, même après un terminateur.
    public func validateEmpty(userMemory: Data) throws {
        guard userMemory.count == userByteCount else { throw TagError.unreadable }
        let bytes = Array(userMemory)
        let allZero = bytes.allSatisfy { $0 == 0 }
        let emptyTLV = Array(bytes.prefix(4)) == [3, 0, 0xFE, 0]
            && bytes.dropFirst(4).allSatisfy { $0 == 0 }
        let terminatorOnly = bytes.first == 0xFE && bytes.dropFirst().allSatisfy { $0 == 0 }
        guard allZero || emptyTLV || terminatorOnly else { throw TagError.notNDEFCompatible }
    }

    /// Aucune écriture des verrous, du mot de passe ou de la configuration.
    public func validateWritable(header: Data, configuration: Data, locks: Data) throws {
        guard header.count == 16, configuration.count == 16, locks.count == 16 else {
            throw TagError.unreadable
        }
        let h = Array(header), c = Array(configuration), l = Array(locks)
        let cc = Data(h[12..<16])
        guard cc == capabilityContainer || cc == Data(repeating: 0, count: 4) else {
            if h[15] & 0x0F != 0 { throw TagError.readOnly }
            throw TagError.notNDEFCompatible
        }
        guard h[10] == 0, h[11] == 0, l.prefix(3).allSatisfy({ $0 == 0 }),
              c[3] > configurationPage + 3 else { throw TagError.readOnly }
        // Un miroir UID/compteur actif peut changer les octets relus.
        guard c[0] & 0xC0 == 0 else { throw TagError.notNDEFCompatible }
    }

    /// Pages utilisateur complètes avec TLV NDEF et terminateur, sans dépasser le CC.
    public func encodedPages(records: [NDEFRecord]) throws -> Data {
        let message = NDEFCodec.encode(records)
        let overhead = message.count < 255 ? 3 : 5
        let size = Int(ccSize) * 8
        guard !message.isEmpty, message.count + overhead <= size else {
            throw TagError.insufficientCapacity(maxMessageLength: size - (size > 257 ? 5 : 3))
        }
        var result = Data([3])
        if message.count < 255 {
            result.append(UInt8(message.count))
        } else {
            result.append(contentsOf: [0xFF, UInt8(message.count >> 8), UInt8(message.count & 0xFF)])
        }
        result.append(message)
        result.append(0xFE)
        while result.count % 4 != 0 { result.append(0) }
        return result
    }
}
