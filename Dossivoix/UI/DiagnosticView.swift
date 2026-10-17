import SwiftUI

/// Écran Diagnostic : détail brut des dernières étiquettes lues, à partager
/// (par message, e-mail…) via la feuille de partage. Rien n'est envoyé automatiquement.
struct DiagnosticView: View {
    let log: DiagnosticLog

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Aucune étiquette lue depuis l'ouverture de l'app.")
                    .foregroundStyle(.secondary)
            }
            ForEach(log.entries) { entry in
                Section {
                    Text(entry.report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink(item: entry.report) {
                        Label("Partager ce rapport", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    HStack {
                        if entry.hasUnrecognizedContent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .accessibilityLabel("Contenu non reconnu")
                        }
                        Text(entry.summary)
                        Spacer()
                        Text(entry.date, style: .time)
                    }
                }
            }
        }
        .navigationTitle("Diagnostic")
        .toolbar {
            if !log.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: log.fullReport) {
                        Label("Tout partager", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
