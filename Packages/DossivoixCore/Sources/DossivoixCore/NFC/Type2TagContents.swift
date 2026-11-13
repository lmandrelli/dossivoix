import Foundation

/// Le contenu de l'étiquette est son message NDEF actif, pas les octets résiduels
/// de sa mémoire. Un CC valide sans encapsulation NDEF représente une puce à initialiser.
public struct Type2TagContents: Sendable {
    private let layout: Type2NDEFLayout?
    private let memory: Data
    public let records: [NDEFRecord]
    public let capacity: Int
    public let isReadOnly: Bool
    public var message: Data { NDEFCodec.encode(records) }
    public var maxMessageLength: Int { max(0, capacity - (capacity > 257 ? 5 : 3)) }

    public init(capabilityContainer cc: Data, memory: Data) throws {
        guard cc.count == 4, cc[0] == 0xE1, cc[1] >> 4 == 1, cc[2] > 0,
              cc[3] >> 4 == 0, memory.count >= 8, memory.count <= Int(cc[2]) * 8 else { throw TagError.unreadable }
        self.memory = memory
        capacity = Int(cc[2]) * 8
        isReadOnly = cc[3] & 0x0F != 0
        if let parsed = try? Type2NDEFLayout(capabilityContainer: cc, memory: memory) {
            layout = parsed
            // Un TLV NDEF actif mais endommagé ne doit pas être assimilé à une vierge.
            records = parsed.message.isEmpty ? [] : (try? NDEFCodec.decode(parsed.message))
                ?? [NDEFRecord(typeNameFormat: .unknown, type: Data(), payload: parsed.message)]
        } else {
            if memory.count < capacity, let first = memory.first, [0, 1, 2, 3, 0xFE].contains(first) {
                throw TagError.unreadable // Il manque des pages pour conclure sur le TLV.
            }
            layout = nil
            // Pas de message NDEF : ne pas rechercher/reconstituer des anciens textes
            // dans les octets bruts, qui ne sont pas des enregistrements actifs.
            records = []
        }
    }

    public func checkCapacity(for records: [NDEFRecord]) throws {
        if let layout { try layout.checkCapacity(for: records); return }
        let count = NDEFCodec.encode(records).count
        guard count + (count < 255 ? 3 : 5) <= capacity else {
            throw TagError.insufficientCapacity(maxMessageLength: maxMessageLength)
        }
    }

    public func clearingWrites() throws -> [Type2NDEFLayout.PageWrite] {
        if let layout { return try layout.clearingWrites() }
        guard !isReadOnly else { throw TagError.readOnly }
        return [.init(page: 4, bytes: Data([3, 0, 0xFE, memory[3]]))]
    }

    public func initializationWrites(replacingExisting: Bool = false) throws -> [Type2NDEFLayout.PageWrite] {
        if let layout { return try layout.initializationWrites(replacingExisting: replacingExisting) }
        guard !isReadOnly else { throw TagError.readOnly }
        guard memory.count >= 8 else { throw TagError.insufficientCapacity(maxMessageLength: 0) }
        // Aucune donnée NDEF active. Créer une structure vide, puis laisser CoreNFC
        // écrire le texte normalement. Ne jamais modifier les verrous/configurations.
        return [
            .init(page: 5, bytes: Data([0, 0xFE, memory[6], memory[7]])),
            .init(page: 4, bytes: Data([3, 3, 0xD0, 0]))
        ]
    }
}
