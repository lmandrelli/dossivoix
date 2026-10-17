import Foundation

/// Format des étiquettes écrites par le téléphone Kapsys SmartVision 2.
///
/// Relevé avec NXP TagInfo sur une étiquette existante (NTAG 213), message de 54 octets :
/// 1. TNF Media, type "text/plain", payload "TEXT"  → marqueur ajouté par l'appli Kapsys ;
/// 2. TNF Media, type "text/plain", payload = nom du dossier en UTF-8, suivi d'un espace.
/// Aucun identifiant d'enregistrement.
///
/// Le marqueur et l'espace final restent à confirmer par un test croisé avec le SmartVision :
/// ils sont donc réglables.
public struct SmartVisionFormat: Equatable, Sendable {
    /// Type MIME des deux enregistrements.
    public static let mimeType = "text/plain"
    /// Contenu du marqueur (premier enregistrement).
    public static let markerText = "TEXT"

    /// Écrire le marqueur "TEXT" en premier enregistrement.
    public var writesMarker: Bool
    /// Ajouter un espace à la fin du nom, comme sur l'étiquette relevée.
    public var appendsTrailingSpace: Bool

    public init(writesMarker: Bool = true, appendsTrailingSpace: Bool = true) {
        self.writesMarker = writesMarker
        self.appendsTrailingSpace = appendsTrailingSpace
    }

    /// Réglages utilisés par l'app : reproduisent à l'identique l'étiquette relevée.
    public static let standard = SmartVisionFormat()

    /// Enregistrements à écrire pour un nom de dossier.
    /// Le nom est seulement nettoyé (espaces) ; la majuscule initiale est appliquée en amont,
    /// pour que le nom confirmé à voix haute soit exactement celui écrit.
    public func records(forFolderName name: String) -> [NDEFRecord] {
        var text = FolderName.cleaned(name)
        if appendsTrailingSpace { text += " " }

        var records: [NDEFRecord] = []
        if writesMarker {
            records.append(Self.textRecord(Self.markerText))
        }
        records.append(Self.textRecord(text))
        return records
    }

    /// Taille en octets du message NDEF qui serait écrit pour ce nom.
    public func messageLength(forFolderName name: String) -> Int {
        NDEFCodec.encode(records(forFolderName: name)).count
    }

    private static func textRecord(_ text: String) -> NDEFRecord {
        NDEFRecord(
            typeNameFormat: .media,
            type: Data(mimeType.utf8),
            payload: Data(text.utf8)
        )
    }
}
