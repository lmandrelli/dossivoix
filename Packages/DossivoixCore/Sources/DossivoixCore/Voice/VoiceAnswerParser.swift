import Foundation

/// Réponse vocale simple, une fois interprétée.
public enum VoiceAnswer: Equatable, Sendable {
    case yes
    case no
    case restart
    case cancel
    /// « encore » : lire (ou réessayer) une autre fois.
    case again
    /// « écrire » : passer à l'écriture.
    case write
}

/// Mise en forme d'un texte reconnu avant comparaison :
/// minuscules, sans accents, ponctuation et apostrophes remplacées par des espaces.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "fr_FR"))
        let spaced = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}

/// Interprète les réponses courtes (oui / non / recommencer / annuler / encore / écrire).
///
/// La phrase reconnue est cherchée mot à mot : « oui c'est ça » → oui.
/// Si des réponses contradictoires sont trouvées (« non… oui »), la réponse est jugée
/// incompréhensible (nil) et la question sera reposée : mieux vaut redemander que se tromper.
public enum VoiceAnswerParser {
    /// Expressions reconnues, déjà normalisées (sans accents ni apostrophes).
    /// L'ordre compte : les expressions longues sont retirées du texte avant les courtes,
    /// pour que « pas d'accord » ne soit pas compris comme « d'accord », ni
    /// « encore une fois » (recommencer) comme « encore ».
    static let vocabulary: [(answer: VoiceAnswer, phrases: [String])] = [
        (.cancel, ["laisse tomber", "annuler", "annule", "annulez", "arrete", "arreter", "arretez",
                   "stop", "abandonner", "abandonne", "quitter", "rien"]),
        (.restart, ["encore une fois", "recommencer", "recommence", "recommencez", "refaire", "refais",
                    "reessayer", "redire", "a nouveau"]),
        (.no, ["c est pas ca", "ce n est pas ca", "pas d accord", "pas bon", "pas ca", "non", "nan",
               "faux", "incorrect", "garder", "garde", "negatif"]),
        (.yes, ["d accord", "c est ca", "c est bon", "tout a fait", "bien sur", "vas y", "allez y",
                "oui", "ouais", "ok", "okay", "exact", "exactement", "parfait", "voila", "valide",
                "valider", "confirme", "confirmer", "remplace", "remplacer", "correct", "absolument"]),
        (.again, ["une autre", "encore", "suivante", "suivant", "continuer", "continue", "lire", "relire"]),
        (.write, ["nouveau nom", "ecrire", "ecris", "ecrivez", "ecriture", "renommer", "renomme", "changer"]),
    ]

    /// Réponse comprise, ou nil si rien de clair n'a été dit.
    public static func parse(_ text: String) -> VoiceAnswer? {
        var remaining = " " + TextNormalizer.normalize(text) + " "
        var found: [VoiceAnswer] = []

        for (answer, phrases) in vocabulary {
            for phrase in phrases where remaining.contains(" \(phrase) ") {
                // L'expression est retirée pour ne pas être recomptée par une plus courte.
                remaining = remaining.replacingOccurrences(of: " \(phrase) ", with: " | ")
                if !found.contains(answer) { found.append(answer) }
            }
        }
        if found.count == 1 { return found[0] }
        // « oui, encore » ou « oui, écrire » : la réponse précise l'emporte sur « oui ».
        if found.count == 2, found.contains(.yes), let other = found.first(where: { $0 == .again || $0 == .write }) {
            return other
        }
        return nil
    }

    /// Vrai si le texte dicté n'est qu'une demande d'annulation (« annuler », « stop »…),
    /// et non un nom de dossier.
    public static func isStandaloneCancel(_ text: String) -> Bool {
        let normalized = TextNormalizer.normalize(text)
        let cancelPhrases = vocabulary.first { $0.answer == .cancel }?.phrases ?? []
        return cancelPhrases.contains(normalized)
    }
}
