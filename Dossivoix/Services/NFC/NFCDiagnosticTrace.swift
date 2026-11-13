import Foundation

@MainActor
protocol TagDiagnosticProviding: AnyObject {
    var lastDiagnosticReport: String { get }
}

/// Relevé temporaire, local, incluant l'UID pour identifier la puce testée. Même durée de vie que la session applicative.
/// Aucun envoi automatique ; le partage est déclenché depuis l'écran Diagnostic.
@MainActor
final class NFCDiagnosticTrace {
    private var lines: [String] = []
    var report: String { lines.joined(separator: "\n") }

    func reset() { lines = [] }
    func record(_ line: String) {
        lines.append(line)
        #if DEBUG
        print("NFC-DIAG " + line)
        #endif
    }
}
