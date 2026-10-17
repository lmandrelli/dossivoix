import Foundation

/// État d'écriture d'une étiquette, tel que l'étiquette le signale.
public enum TagWriteStatus: Sendable {
    case readWrite
    case readOnly
    case notSupported
}

/// Décision prise une fois l'étiquette approchée et son contenu actuel lu.
public enum WriteDecision: Equatable, Sendable {
    /// Écrire le nouveau contenu.
    case write
    /// L'étiquette contient déjà exactement ce contenu : rien à faire.
    case alreadyUpToDate
    /// L'étiquette contient autre chose : demander confirmation, puis écrire au 2e passage.
    case askReplace(existing: DecodedTag)
    /// Écriture impossible.
    case refuse(TagError)
}

/// Règles d'écriture, indépendantes de CoreNFC.
///
/// - 1er passage (`expectedCurrent == nil`) : une étiquette vide, ou portant déjà le même nom,
///   est écrite directement ; sinon on demande confirmation avant de remplacer.
/// - 2e passage (`expectedCurrent` = contenu lu au 1er passage) : on n'écrit que si le contenu
///   est toujours le même, pour ne pas écraser une autre étiquette par erreur.
/// - On n'écrit jamais sur une étiquette verrouillée, et on ne la verrouille jamais.
public enum WritePlanner {
    public static func decide(
        status: TagWriteStatus,
        capacity: Int,
        current: [NDEFRecord],
        desired: [NDEFRecord],
        expectedCurrent: [NDEFRecord]?
    ) -> WriteDecision {
        if status == .notSupported {
            return .refuse(.notNDEFCompatible)
        }
        if let expectedCurrent, current != expectedCurrent {
            return .refuse(.differentTag)
        }
        if current == desired {
            return .alreadyUpToDate
        }
        if status == .readOnly {
            return .refuse(.readOnly)
        }
        if NDEFCodec.encode(desired).count > capacity {
            return .refuse(.insufficientCapacity(maxMessageLength: capacity))
        }
        if expectedCurrent != nil {
            // Remplacement déjà confirmé.
            return .write
        }

        let existing = TagDecoder.decode(current)
        if existing.outcome == .empty {
            return .write
        }
        // Même nom, format différent (ex. sans marqueur) : rien n'est perdu, on réécrit sans demander.
        let sameName = existing.folderName != nil
            && existing.folderName == TagDecoder.decode(desired).folderName
            && !existing.hasUnrecognizedParts
        return sameName ? .write : .askReplace(existing: existing)
    }

    /// Vérifie la relecture après écriture : contenu identique, ou à défaut même nom décodé
    /// (au cas où le système présenterait les enregistrements un peu différemment).
    public static func isVerified(readBack: [NDEFRecord], desired: [NDEFRecord]) -> Bool {
        if readBack == desired { return true }
        let name = TagDecoder.decode(desired).folderName
        return name != nil && TagDecoder.decode(readBack).folderName == name
    }
}
