import Foundation

/// Résultat de l'interprétation d'une étiquette.
public struct DecodedTag: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Un nom de dossier a été trouvé (déjà nettoyé).
        case folderName(String)
        /// L'étiquette ne contient rien (aucun enregistrement, ou seulement des textes vides).
        case empty
        /// Le contenu n'a pas pu être interprété : annoncer « format non reconnu ».
        case unrecognized
    }

    public let outcome: Outcome
    /// Tous les enregistrements lus, pour le diagnostic.
    public let records: [NDEFRecord]
    /// Enregistrements qu'on ne sait pas interpréter (même si un nom a été trouvé à côté).
    public let unrecognizedRecords: [NDEFRecord]

    /// Vrai si une partie du contenu n'a pas été comprise : à signaler oralement
    /// et à proposer dans l'écran Diagnostic.
    public var hasUnrecognizedParts: Bool { !unrecognizedRecords.isEmpty }

    /// Nom du dossier, s'il y en a un.
    public var folderName: String? {
        if case .folderName(let name) = outcome { return name }
        return nil
    }
}

/// Interprétation tolérante du contenu d'une étiquette.
///
/// Règles :
/// - textes MIME "text/plain" (format SmartVision) et textes « Well-known » (RTD_TEXT) acceptés ;
/// - le marqueur "TEXT" est ignoré s'il est le premier enregistrement et que d'autres suivent ;
/// - espaces superflus supprimés ;
/// - plusieurs textes : ils sont joints par une virgule ;
/// - tout le reste est conservé comme « non reconnu », jamais ignoré en silence.
public enum TagDecoder {
    public static func decode(_ records: [NDEFRecord]) -> DecodedTag {
        var names: [String] = []
        var unrecognized: [NDEFRecord] = []
        var skippedMarker = false

        for (index, record) in records.enumerated() {
            if index == 0, records.count > 1, isMarker(record) {
                skippedMarker = true
                continue
            }
            switch classify(record) {
            case .text(let text):
                let name = FolderName.cleaned(text)
                if !name.isEmpty { names.append(name) }
            case .blank:
                break
            case .unrecognized:
                unrecognized.append(record)
            }
        }

        let outcome: DecodedTag.Outcome
        if !names.isEmpty {
            outcome = .folderName(names.joined(separator: ", "))
        } else if unrecognized.isEmpty && !skippedMarker {
            outcome = .empty
        } else {
            // Un marqueur seul, ou des enregistrements inconnus : on ne sait pas lire.
            outcome = .unrecognized
        }
        return DecodedTag(outcome: outcome, records: records, unrecognizedRecords: unrecognized)
    }

    // MARK: - Classement d'un enregistrement

    private enum RecordKind {
        case text(String)
        case blank
        case unrecognized
    }

    private static func classify(_ record: NDEFRecord) -> RecordKind {
        switch record.typeNameFormat {
        case .empty:
            return .blank
        case .media where isPlainTextMIME(record.type):
            guard let text = String(data: record.payload, encoding: .utf8) else { return .unrecognized }
            return .text(text)
        case .wellKnown where record.type == Data("T".utf8):
            guard let text = wellKnownText(record.payload) else { return .unrecognized }
            return .text(text)
        default:
            return .unrecognized
        }
    }

    /// Le marqueur Kapsys : texte MIME dont le contenu est exactement "TEXT".
    private static func isMarker(_ record: NDEFRecord) -> Bool {
        record.typeNameFormat == .media
            && isPlainTextMIME(record.type)
            && record.payload == Data(SmartVisionFormat.markerText.utf8)
    }

    /// "text/plain", sans tenir compte de la casse ni d'éventuels paramètres ("; charset=utf-8").
    private static func isPlainTextMIME(_ type: Data) -> Bool {
        guard let mime = String(data: type, encoding: .utf8) else { return false }
        let base = mime.split(separator: ";").first.map(String.init) ?? mime
        return base.trimmingCharacters(in: .whitespaces).lowercased() == SmartVisionFormat.mimeType
    }

    /// Décode le payload d'un enregistrement « Well-known Text » (RTD_TEXT) :
    /// octet de statut (bit 7 = UTF-16, bits 0-5 = longueur du code langue), code langue, texte.
    private static func wellKnownText(_ payload: Data) -> String? {
        let bytes = [UInt8](payload)
        guard let status = bytes.first else { return nil }
        let isUTF16 = status & 0x80 != 0
        let languageLength = Int(status & 0x3F)
        guard bytes.count >= 1 + languageLength else { return nil }
        let textBytes = Array(bytes[(1 + languageLength)...])

        if !isUTF16 {
            return String(bytes: textBytes, encoding: .utf8)
        }
        // UTF-16 : gros-boutiste par défaut, sauf si une marque d'ordre (BOM) indique l'inverse.
        let hasBOM = textBytes.starts(with: [0xFE, 0xFF]) || textBytes.starts(with: [0xFF, 0xFE])
        return String(bytes: textBytes, encoding: hasBOM ? .utf16 : .utf16BigEndian)
    }
}
