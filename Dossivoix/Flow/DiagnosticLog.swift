import Foundation
import Observation
import DossivoixCore

/// Une lecture conservée pour l'écran Diagnostic.
struct DiagnosticEntry: Identifiable {
    let id = UUID()
    let date: Date
    /// Ce qui a été annoncé.
    let summary: String
    /// Vrai si une partie du contenu n'a pas été comprise.
    let hasUnrecognizedContent: Bool
    /// Rapport complet, à partager.
    let report: String
}

/// Dernières lectures, gardées en mémoire uniquement (rien n'est enregistré ni envoyé).
/// Elles ne quittent l'iPhone que si l'utilisatrice les partage elle-même.
@MainActor
@Observable
final class DiagnosticLog {
    /// Nombre maximal de lectures conservées.
    static let capacity = 20

    private(set) var entries: [DiagnosticEntry] = []

    /// Ajoute une lecture (la plus récente en premier).
    func add(_ decoded: DecodedTag, date: Date = .now) {
        let summary = Phrases.readResult(decoded)
        let report = """
            \(AppIdentity.name) – diagnostic du \(date.formatted(date: .numeric, time: .standard))
            Annonce : \(summary)

            \(TagDiagnostic.report(for: decoded.records))
            """
        let entry = DiagnosticEntry(
            date: date,
            summary: summary,
            hasUnrecognizedContent: decoded.outcome == .unrecognized || decoded.hasUnrecognizedParts,
            report: report
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Tous les rapports, pour un partage groupé.
    var fullReport: String {
        entries.map(\.report).joined(separator: "\n\n----------\n\n")
    }
}
