import Foundation

/// Lecture de la structure NFC Forum Type 2, sans identifier une révision de puce.
/// Les TLV de contrôle d'usine ne sont pas du contenu utilisateur et restent intacts.
public struct Type2NDEFLayout: Sendable {
    public let capacity: Int
    public let isReadOnly: Bool
    public let message: Data
    private let memory: Data
    private let messageOffset: Int
    private let endOffset: Int
    private let terminatorOffset: Int?
    private let reservedRanges: [Range<Int>]

    public init(capabilityContainer: Data, memory: Data) throws {
        let cc = Array(capabilityContainer)
        guard cc.count == 4, cc[0] == 0xE1, cc[1] >> 4 == 1,
              cc[2] > 0, cc[3] >> 4 == 0 else { throw TagError.notNDEFCompatible }
        capacity = Int(cc[2]) * 8
        isReadOnly = cc[3] & 0x0F != 0
        guard memory.count == capacity else { throw TagError.unreadable }
        self.memory = memory
        let bytes = Array(memory)
        var cursor = 0
        var found: (offset: Int, end: Int, message: Data)?
        var insertion = 0
        var reserved: [Range<Int>] = []
        var terminator: Int?
        while cursor < bytes.count {
            let start = cursor
            let type = bytes[cursor]
            cursor += 1
            if type == 0 { continue }
            if type == 0xFE { terminator = start; break }
            guard cursor < bytes.count else { throw TagError.unreadable }
            var length = Int(bytes[cursor]); cursor += 1
            if length == 0xFF {
                guard cursor + 2 <= bytes.count else { throw TagError.unreadable }
                length = Int(bytes[cursor]) * 256 + Int(bytes[cursor + 1]); cursor += 2
            }
            guard cursor + length <= bytes.count else { throw TagError.unreadable }
            switch type {
            case 1, 2:
                // Informations sur les verrous/réservations, conservées octet pour octet.
                guard length == 3 else { throw TagError.unreadable }
                let pageSize = 1 << Int(bytes[cursor + 2] & 0x0F)
                let address = Int(bytes[cursor] >> 4) * pageSize + Int(bytes[cursor] & 0x0F)
                let amount = bytes[cursor + 1] == 0 ? 256 : Int(bytes[cursor + 1])
                let reservedSize = type == 1 ? (amount + 7) / 8 : amount
                reserved.append(address..<address + reservedSize)
                insertion = cursor + length
            case 3:
                found = (start, cursor + length, Data(bytes[cursor..<cursor + length]))
            default:
                // Un TLV propriétaire ne doit pas être effacé comme s'il était vide.
                throw TagError.notNDEFCompatible
            }
            if found != nil { break }
            cursor += length
        }
        terminatorOffset = found.map { $0.end < bytes.count && bytes[$0.end] == 0xFE ? $0.end : nil } ?? terminator
        reservedRanges = reserved
        messageOffset = found?.offset ?? insertion
        endOffset = found?.end ?? insertion
        message = found?.message ?? Data()
    }

    public func checkCapacity(for records: [NDEFRecord]) throws {
        let count = NDEFCodec.encode(records).count
        let overhead = count < 255 ? 3 : 5
        guard count + overhead <= capacity - messageOffset else {
            throw TagError.insufficientCapacity(maxMessageLength: max(0, capacity - messageOffset - overhead))
        }
    }

    public struct PageWrite: Equatable, Sendable {
        public let page: UInt8
        public let bytes: Data
        public init(page: UInt8, bytes: Data) { self.page = page; self.bytes = bytes }
    }

    /// Prépare uniquement un NDEF vide valide. Le texte sera écrit ensuite par CoreNFC.
    /// Le CC, les contrôles TLV, les verrous et les données après la zone utilisée restent inchangés.
    public func initializationWrites(replacingExisting: Bool = false) throws -> [PageWrite] {
        if message == Data([0xD0, 0, 0]) { return [] }
        guard message.isEmpty || replacingExisting else { throw TagError.notNDEFCompatible }
        guard !isReadOnly else { throw TagError.readOnly }
        let emptyNDEF: [UInt8] = [3, 3, 0xD0, 0, 0, 0xFE]
        guard messageOffset + emptyNDEF.count <= capacity else {
            throw TagError.insufficientCapacity(maxMessageLength: 0)
        }
        let original = Array(memory)
        // Ne pas écraser un autre TLV ni un résidu non nul en étendant le message vide.
        let extensionBytes = original[min(endOffset, messageOffset + emptyNDEF.count)..<messageOffset + emptyNDEF.count]
        guard replacingExisting || extensionBytes.enumerated().allSatisfy({ entry in
            let index = endOffset + entry.offset
            return entry.element == 0
                || entry.element == emptyNDEF[index - messageOffset]
                || (index == terminatorOffset && entry.element == 0xFE)
        }) else {
            throw TagError.notNDEFCompatible
        }
        var updated = original
        updated.replaceSubrange(messageOffset..<messageOffset + emptyNDEF.count, with: emptyNDEF)
        let firstPage = messageOffset / 4
        let lastPage = (messageOffset + emptyNDEF.count - 1) / 4
        // Ne jamais toucher aux octets réservés décrits par les TLV de contrôle.
        let writtenRange = (16 + firstPage * 4)..<(16 + (lastPage + 1) * 4)
        guard !reservedRanges.contains(where: { $0.overlaps(writtenRange) }) else {
            throw TagError.notNDEFCompatible
        }
        // La longueur peut se trouver sur la page suivante : la publier en dernier.
        let lengthPage = (messageOffset + 1) / 4
        let pageIndices = (firstPage...lastPage).filter { $0 != lengthPage } + [lengthPage]
        return pageIndices.compactMap { index in
            let range = index * 4..<index * 4 + 4
            guard Array(original[range]) != Array(updated[range]) else { return nil }
            return PageWrite(page: UInt8(4 + index), bytes: Data(updated[range]))
        }
    }
}

/// Utilisé uniquement si le CC est absent. La révision et la capacité d'antenne
/// ne définissent pas la capacité de stockage : ne pas les filtrer.
public enum NTAGCapabilityContainer {
    public static func forVersion(_ version: Data) throws -> Data {
        let v = Array(version)
        guard v.count == 8, v[1] == 4, v[2] == 4 else { throw TagError.notNDEFCompatible }
        let size: UInt8
        switch v[6] {
        case 0x0F: size = 0x12
        case 0x11: size = 0x3E
        case 0x13: size = 0x6D
        default: throw TagError.notNDEFCompatible
        }
        return Data([0xE1, 0x10, size, 0])
    }
}
