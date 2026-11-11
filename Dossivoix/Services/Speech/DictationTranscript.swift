import Foundation

/// Position dans l'audio de la session, pas une horloge murale. Une fin d'énoncé
/// (métadonnées Speech) n'est pas forcément la fin de la tâche de reconnaissance.
struct SpeechUtterance: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let isComplete: Bool
}

/// Speech peut livrer soit tout le texte, soit seulement l'énoncé suivant une pause.
/// Garder les énoncés achevés et remplacer uniquement l'hypothèse encore révisable.
struct DictationTranscript {
    private struct Part {
        let text: String
        let range: SpeechUtterance?
    }
    private var completed: [Part] = []
    private var pending: Part?

    mutating func receive(_ text: String, utterance: SpeechUtterance?) -> String {
        guard !text.isEmpty else { return rendered }
        if let utterance {
            // Un résultat cumulatif ou corrigé remplace les énoncés qu'il couvre.
            // Un nouvel énoncé horodaté reste distinct, même avec les mêmes mots.
            if let pending, let previous = pending.range,
               utterance.start >= previous.end, previous.end > previous.start {
                completed.append(pending)
            }
            completed.removeAll { part in
                guard let range = part.range else { return true }
                return range.end > utterance.start + 0.01
            }
            let part = Part(text: text, range: utterance)
            if utterance.isComplete {
                completed.append(part)
                pending = nil
            } else { pending = part }
        } else {
            // Les hypothèses partielles peuvent avoir des timestamps tous à zéro.
            // Elles restent révisables ; on ne concatène jamais chaque callback.
            pending = Part(text: text, range: nil)
        }
        return rendered
    }

    private var rendered: String {
        let prefix = completed.map(\.text).joined(separator: " ")
        guard let pending else { return prefix }
        guard !prefix.isEmpty else { return pending.text }
        if pending.range == nil {
            // Compatibilité avec les moteurs qui continuent à retourner le texte
            // cumulatif, et avec le rappel identique qui suit une fin d'énoncé.
            if pending.text == prefix || pending.text.hasPrefix(prefix + " ") { return pending.text }
            if pending.text == completed.last?.text { return prefix }
        }
        return prefix + " " + pending.text
    }
}
