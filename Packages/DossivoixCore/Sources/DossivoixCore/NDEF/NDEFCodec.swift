import Foundation

/// Erreurs possibles lors de la lecture d'octets NDEF bruts.
public enum NDEFCodecError: Error, Equatable {
    /// Aucune donnée à décoder.
    case emptyData
    /// Les données s'arrêtent au milieu d'un enregistrement (position de l'octet manquant).
    case truncated(offset: Int)
    /// Enregistrement découpé en fragments (bit CF) : non géré, jamais vu sur ces étiquettes.
    case chunkedRecordNotSupported
}

/// Conversion entre octets NDEF bruts et enregistrements.
///
/// Sur iPhone, c'est CoreNFC qui lit et écrit les octets ; ce codec sert à :
/// - calculer la taille exacte d'un message avant l'écriture ;
/// - tester le format avec les octets réels relevés sur les étiquettes ;
/// - produire le diagnostic.
public enum NDEFCodec {
    // Bits de l'octet d'en-tête de chaque enregistrement.
    private static let messageBegin: UInt8 = 0x80 // MB : premier enregistrement
    private static let messageEnd: UInt8 = 0x40   // ME : dernier enregistrement
    private static let chunkFlag: UInt8 = 0x20    // CF : fragment
    private static let shortRecord: UInt8 = 0x10  // SR : longueur du payload sur 1 octet
    private static let idLength: UInt8 = 0x08     // IL : identifiant présent
    private static let tnfMask: UInt8 = 0x07

    /// Encode un message NDEF. Les enregistrements courts (payload < 256 octets)
    /// utilisent la forme « short record », comme le SmartVision.
    public static func encode(_ records: [NDEFRecord]) -> Data {
        var data = Data()
        for (index, record) in records.enumerated() {
            precondition(record.type.count <= 255, "Type NDEF trop long")
            precondition(record.identifier.count <= 255, "Identifiant NDEF trop long")

            let isShort = record.payload.count < 256
            var header = record.typeNameFormat.rawValue
            if index == 0 { header |= messageBegin }
            if index == records.count - 1 { header |= messageEnd }
            if isShort { header |= shortRecord }
            if !record.identifier.isEmpty { header |= idLength }

            data.append(header)
            data.append(UInt8(record.type.count))
            if isShort {
                data.append(UInt8(record.payload.count))
            } else {
                // Longueur sur 4 octets, poids fort en premier.
                let length = UInt32(record.payload.count)
                data.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: length >> $0) })
            }
            if !record.identifier.isEmpty {
                data.append(UInt8(record.identifier.count))
            }
            data.append(record.type)
            data.append(record.identifier)
            data.append(record.payload)
        }
        return data
    }

    /// Décode un message NDEF. S'arrête au premier enregistrement marqué « dernier » (ME) ;
    /// les octets suivants éventuels sont ignorés.
    public static func decode(_ data: Data) throws -> [NDEFRecord] {
        var reader = ByteReader(bytes: [UInt8](data))
        guard !reader.isAtEnd else { throw NDEFCodecError.emptyData }

        var records: [NDEFRecord] = []
        while !reader.isAtEnd {
            let header = try reader.readByte()
            if header & chunkFlag != 0 { throw NDEFCodecError.chunkedRecordNotSupported }

            let typeLength = Int(try reader.readByte())
            let payloadLength: Int
            if header & shortRecord != 0 {
                payloadLength = Int(try reader.readByte())
            } else {
                payloadLength = try reader.readBytes(4).reduce(0) { ($0 << 8) | Int($1) }
            }
            let identifierLength = header & idLength != 0 ? Int(try reader.readByte()) : 0

            let type = try reader.readBytes(typeLength)
            let identifier = try reader.readBytes(identifierLength)
            let payload = try reader.readBytes(payloadLength)

            // Le TNF est sur 3 bits : toutes les valeurs existent dans l'énumération.
            let tnf = NDEFTypeNameFormat(rawValue: header & tnfMask) ?? .reserved
            records.append(NDEFRecord(
                typeNameFormat: tnf,
                type: Data(type),
                identifier: Data(identifier),
                payload: Data(payload)
            ))

            if header & messageEnd != 0 { break }
        }
        return records
    }
}

/// Petit lecteur séquentiel d'octets, qui signale proprement les données tronquées.
private struct ByteReader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else { throw NDEFCodecError.truncated(offset: offset) }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else {
            throw NDEFCodecError.truncated(offset: bytes.count)
        }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }
}
