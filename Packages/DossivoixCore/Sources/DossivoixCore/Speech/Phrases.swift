import Foundation

/// Toutes les phrases affichées ou prononcées par l'app, en un seul endroit.
/// Phrases courtes et simples : elles sont faites pour être entendues.
public enum Phrases {
    /// Opération en cours, pour adapter certains messages.
    public enum Operation: Sendable {
        case reading
        case writing
    }

    // MARK: - Accueil et lecture

    public static let welcome = "Appuyez sur Lire ou sur Écrire."
    public static let approachTag = "Approchez l'étiquette."
    public static let emptyTag = "Étiquette vide."
    public static let unrecognizedFormat = "Étiquette d'un format non reconnu."
    public static let alsoUnrecognizedContent = "Cette étiquette contient aussi des informations non reconnues."

    /// Annonce du résultat d'une lecture.
    public static func readResult(_ decoded: DecodedTag) -> String {
        switch decoded.outcome {
        case .folderName(let name):
            return decoded.hasUnrecognizedParts ? "\(name). \(alsoUnrecognizedContent)" : name
        case .empty:
            return emptyTag
        case .unrecognized:
            return unrecognizedFormat
        }
    }

    // MARK: - Feuille système NFC (texte affiché par iOS pendant la session)

    public static let nfcSheetApproach = "Approchez le haut de l'iPhone de l'étiquette."
    public static let nfcSheetSeveralTags = "Plusieurs étiquettes détectées. N'en approchez qu'une seule."
    public static let nfcSheetReadDone = "Étiquette lue."

    // MARK: - Erreurs

    /// Message simple pour une erreur NFC.
    public static func message(for error: TagError, during operation: Operation) -> String {
        switch error {
        case .readingUnavailable:
            return "Cet appareil ne peut pas utiliser les étiquettes NFC."
        case .userCanceled:
            return operation == .reading ? "Lecture annulée." : "Écriture annulée."
        case .timeout:
            return "Aucune étiquette détectée."
        case .systemBusy:
            return "Le lecteur d'étiquettes est occupé. Réessayez dans un instant."
        case .tagRemoved:
            return "L'étiquette a été retirée trop tôt. Recommencez en la laissant contre l'iPhone."
        case .unreadable:
            return "Étiquette illisible. Recommencez."
        case .notNDEFCompatible:
            return "Cette étiquette n'est pas compatible."
        case .readOnly:
            return "Cette étiquette est verrouillée. On ne peut pas écrire dessus."
        case .insufficientCapacity:
            return "Le nom est trop long pour cette étiquette."
        case .writeFailed:
            return "L'écriture a échoué. Recommencez."
        case .unknown:
            return operation == .reading ? "La lecture a échoué. Recommencez." : "L'écriture a échoué. Recommencez."
        }
    }
}
