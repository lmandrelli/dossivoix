import Foundation
import DossivoixCore

/// Octets de référence d'une étiquette écrite par le SmartVision 2.
///
/// Reconstitués à partir du relevé NXP TagInfo (message de 54 octets, deux short records MIME) :
///   92 0A 04 "text/plain" "TEXT"                       → 17 octets
///   52 0A 18 "text/plain" "Dossier panneau solaire "   → 37 octets
/// TODO : remplacer par le vidage mémoire complet (TagInfo « Full scan ») dès qu'il est disponible.
enum Fixtures {
    static let smartVisionMessage = Data(hexString: """
        92 0A 04 74 65 78 74 2F 70 6C 61 69 6E 54 45 58 54
        52 0A 18 74 65 78 74 2F 70 6C 61 69 6E
        44 6F 73 73 69 65 72 20 70 61 6E 6E 65 61 75 20 73 6F 6C 61 69 72 65 20
        """)!

    static let folderName = "Dossier panneau solaire"

    static let textPlain = Data("text/plain".utf8)

    static func mediaText(_ text: String) -> NDEFRecord {
        NDEFRecord(typeNameFormat: .media, type: textPlain, payload: Data(text.utf8))
    }

    /// Enregistrement « Well-known Text » en UTF-8 avec code langue.
    static func wellKnownText(_ text: String, language: String = "fr") -> NDEFRecord {
        var payload = Data([UInt8(language.utf8.count)])
        payload.append(Data(language.utf8))
        payload.append(Data(text.utf8))
        return NDEFRecord(typeNameFormat: .wellKnown, type: Data("T".utf8), payload: payload)
    }
}
