import Foundation

/// Description textuelle et brute du contenu d'une étiquette, à partager depuis
/// l'écran Diagnostic (feuille de partage). Rien n'est envoyé automatiquement.
public enum TagDiagnostic {
    /// Rapport lisible de tous les enregistrements.
    public static func report(for records: [NDEFRecord]) -> String {
        guard !records.isEmpty else { return "Aucun enregistrement NDEF." }

        var lines: [String] = []
        let messageBytes = NDEFCodec.encode(records)
        lines.append("Message NDEF : \(records.count) enregistrement(s), \(messageBytes.count) octets")
        lines.append("Octets (reconstitués) : \(messageBytes.hexString)")

        for (index, record) in records.enumerated() {
            lines.append("")
            lines.append("Enregistrement \(index + 1)/\(records.count)")
            lines.append(contentsOf: describe(record).map { "  " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    /// Description d'un enregistrement : TNF, type, identifiant, payload en hexadécimal et en UTF-8.
    public static func describe(_ record: NDEFRecord) -> [String] {
        let tnf = record.typeNameFormat
        return [
            "TNF : " + String(format: "0x%02X", tnf.rawValue) + " (\(tnf.label))",
            "Type : \(textAndHex(record.type))",
            "Identifiant : \(record.identifier.isEmpty ? "(aucun)" : textAndHex(record.identifier))",
            "Payload (\(record.payload.count) octets) hex : \(record.payload.isEmpty ? "(vide)" : record.payload.hexString)",
            "Payload UTF-8 : \(utf8Text(record.payload))",
        ]
    }

    private static func textAndHex(_ data: Data) -> String {
        guard !data.isEmpty else { return "(vide)" }
        return "\(utf8Text(data)) [\(data.hexString)]"
    }

    /// Texte entre guillemets si le contenu est de l'UTF-8 valide, sinon une mention explicite.
    private static func utf8Text(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "(non décodable en UTF-8)" }
        return "« \(text) »"
    }
}
