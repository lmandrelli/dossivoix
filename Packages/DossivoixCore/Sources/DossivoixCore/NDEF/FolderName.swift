import Foundation

/// Mise en forme des noms de dossier.
public enum FolderName {
    /// Nettoie un nom lu ou saisi : espaces de début et de fin retirés,
    /// espaces multiples et retours à la ligne remplacés par un seul espace.
    /// La casse n'est pas modifiée.
    public static func cleaned(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Prépare un nom avant écriture : nettoyage, puis majuscule sur la première lettre
    /// (la dictée renvoie souvent tout en minuscules). Le reste du nom est conservé.
    public static func preparedForWriting(_ raw: String) -> String {
        let name = cleaned(raw)
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
