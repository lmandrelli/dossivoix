import Foundation

/// Erreurs NFC, exprimées indépendamment de CoreNFC.
/// L'app traduit les `NFCReaderError` vers ces cas ; les phrases correspondantes sont dans `Phrases`.
public enum TagError: Error, Equatable, Sendable {
    /// L'appareil ne sait pas lire le NFC (simulateur, iPad…).
    case readingUnavailable
    /// L'utilisatrice a touché « Annuler » sur la feuille NFC.
    case userCanceled
    /// Aucune étiquette approchée pendant le délai de la session (60 s environ).
    case timeout
    /// Le lecteur NFC est déjà utilisé.
    case systemBusy
    /// L'étiquette a été éloignée pendant la lecture ou l'écriture.
    case tagRemoved
    /// L'étiquette a mal répondu.
    case unreadable
    /// L'étiquette ne gère pas le format NDEF.
    case notNDEFCompatible
    /// L'étiquette est verrouillée en lecture seule.
    case readOnly
    /// Le message ne tient pas sur l'étiquette (capacité en octets).
    case insufficientCapacity(maxMessageLength: Int)
    /// L'écriture a échoué pour une autre raison (y compris si la relecture ne correspond pas).
    case writeFailed
    /// Au 2e passage, le contenu n'est plus celui vu au 1er : autre étiquette ? Rien n'est écrit.
    case differentTag
    /// Autre erreur, avec sa description technique (pour le diagnostic).
    case unknown(String)
}
