import Foundation

/// Résultat d'une tentative d'écriture.
public enum TagWriteOutcome: Equatable, Sendable {
    /// Écrit et vérifié par relecture. `previous` : contenu remplacé.
    case written(previous: [NDEFRecord])
    /// L'étiquette contenait déjà exactement ce contenu.
    case alreadyUpToDate
    /// L'étiquette contient autre chose : rien n'a été écrit, il faut une confirmation
    /// puis un 2e passage avec le contenu vu (`current`) comme contenu attendu.
    case needsReplaceConfirmation(current: [NDEFRecord])
}
