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

    // MARK: - Questions et réponses vocales

    public static let offerAfterRead =
        "Dites « encore » pour lire une autre étiquette, ou « écrire » pour écrire une étiquette."
    public static let askName = "Dites le nom du dossier."
    public static let askNameAgain = "D'accord. Dites le nom du dossier."
    public static let askShorterName = "Dites un nom plus court."
    public static let didNotHearName = "Je n'ai rien entendu. Dites le nom du dossier."
    public static let didNotUnderstandYesNo = "Je n'ai pas compris. Dites oui, non, ou annuler."
    public static let didNotUnderstandReplace = "Je n'ai pas compris. Dites oui pour remplacer, ou non pour garder l'étiquette."
    public static let useScreen = "Je n'ai pas compris. Vous pouvez utiliser l'écran."
    public static let useScreenButtons = "Je n'ai pas compris. Utilisez les boutons Remplacer ou Annuler à l'écran."
    public static let voiceUnavailable = "La reconnaissance vocale n'est pas disponible. Vous pouvez utiliser l'écran."
    public static let offerAnotherWrite = "Dites « oui » pour écrire une autre étiquette."
    public static let offerRetry = "Dites « encore » pour réessayer."
    public static let writeCanceled = "Écriture annulée."
    public static let stopped = "Annulé."

    /// Demande du nouveau nom, après la lecture d'une étiquette.
    public static func askNewName(for oldName: String) -> String {
        "Dites le nouveau nom pour : \(oldName)."
    }

    /// Confirmation du nom dicté.
    public static func confirmName(_ name: String) -> String {
        "J'ai compris : \(name). C'est bon ?"
    }

    // MARK: - Écriture

    public static let approachTagAgain = "Approchez à nouveau l'étiquette."
    public static let writeCanceledTagUnchanged = "Écriture annulée. L'étiquette n'a pas été modifiée."

    /// Le nom ne tiendra pas sur une NTAG 213 : on le dit avant même d'approcher l'étiquette.
    public static func nameTooLong(_ check: CapacityCheck) -> String {
        "Ce nom est trop long pour une étiquette. "
            + "Raccourcissez-le d'environ \(check.excessBytes) lettre\(check.excessBytes > 1 ? "s" : "")."
    }

    /// Question posée quand l'étiquette contient déjà autre chose.
    public static func askReplace(existing: DecodedTag, newName: String) -> String {
        switch existing.outcome {
        case .folderName(let oldName):
            return "Cette étiquette contient déjà : \(oldName). Voulez-vous la remplacer par : \(newName) ?"
        case .empty, .unrecognized:
            return "Cette étiquette contient déjà des informations d'un format non reconnu. "
                + "Voulez-vous les remplacer par : \(newName) ?"
        }
    }

    public static func written(_ name: String) -> String {
        "Étiquette écrite : \(name)."
    }

    public static func alreadyWritten(_ name: String) -> String {
        "Cette étiquette porte déjà le nom : \(name)."
    }

    // MARK: - Feuille système NFC (texte affiché par iOS pendant la session)

    public static let nfcSheetApproach = "Approchez le haut de l'iPhone de l'étiquette."
    public static let nfcSheetApproachAgain = "Approchez à nouveau le haut de l'iPhone de l'étiquette."
    public static let nfcSheetSeveralTags = "Plusieurs étiquettes détectées. N'en approchez qu'une seule."
    public static let nfcSheetReadDone = "Étiquette lue."
    public static let nfcSheetWriteDone = "Étiquette écrite."
    public static let nfcSheetAlreadyUpToDate = "Étiquette déjà à jour."
    public static let nfcSheetTagInUse = "Étiquette déjà utilisée."

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
        case .differentTag:
            return "Ce n'est pas la même étiquette, ou son contenu a changé. Rien n'a été écrit."
        case .unknown:
            return operation == .reading ? "La lecture a échoué. Recommencez." : "L'écriture a échoué. Recommencez."
        }
    }
}
