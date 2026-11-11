import Foundation

/// Commandes réservées uniquement en suffixe. Le préfixe « texte littéral » désactive
/// leur interprétation pour cette session ; la sortie reste possible à l'écran.
public enum DictationCommand {
    public enum Action: Equatable, Sendable {
        case finish(String)
        /// Arrêter la voix en gardant le texte dicté avant la commande.
        case cancel(String)
    }

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.punctuationCharacters).joined()
    }

    public static func content(_ text: String) -> String {
        let tokens = words(text)
        if normalized(tokens.prefix(2).joined(separator: " ")) == "texte litteral" {
            return tokens.dropFirst(2).joined(separator: " ")
        }
        return text
    }

    public static func action(in text: String) -> Action? {
        let tokens = words(text)
        guard normalized(tokens.prefix(2).joined(separator: " ")) != "texte litteral" else { return nil }
        let suffix = normalized(tokens.suffix(3).joined(separator: " "))
        if suffix == "terminer la dictee" { return .finish(tokens.dropLast(3).joined(separator: " ")) }
        if suffix == "annuler la dictee" { return .cancel(tokens.dropLast(3).joined(separator: " ")) }
        // Compatibilité avec l'annulation seule, jamais au milieu du contenu.
        if VoiceAnswerParser.isStandaloneCancel(text) { return .cancel("") }
        return nil
    }
}
