import Foundation
import Observation
import DossivoixCore

/// Chef d'orchestre des parcours de l'app.
///
/// Étape 2 : lecture seule, résultat affiché à l'écran.
/// La synthèse vocale, l'écriture, la dictée et la machine à états complète viendront ensuite.
@MainActor
@Observable
final class FlowCoordinator {
    /// Dernier message, affiché en grand à l'écran (et bientôt prononcé).
    private(set) var statusMessage = Phrases.welcome
    /// Vrai pendant une session NFC : les boutons sont désactivés.
    private(set) var isBusy = false

    let diagnostics: DiagnosticLog
    private let tagReader: TagReading

    init(tagReader: TagReading, diagnostics: DiagnosticLog? = nil) {
        self.tagReader = tagReader
        self.diagnostics = diagnostics ?? DiagnosticLog()
    }

    /// Coordinateur réel, branché sur CoreNFC.
    static func live() -> FlowCoordinator {
        FlowCoordinator(tagReader: CoreNFCTagService())
    }

    // MARK: - Lecture

    func startReading() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        statusMessage = Phrases.approachTag
        switch await tagReader.readTag() {
        case .success(let records):
            let decoded = TagDecoder.decode(records)
            diagnostics.add(decoded)
            statusMessage = Phrases.readResult(decoded)
        case .failure(let error):
            statusMessage = Phrases.message(for: error, during: .reading)
        }
    }

    // MARK: - Écriture (étape 4)

    func startWriting(folderName: String) async {
        statusMessage = "L'écriture sera disponible dans une prochaine version."
    }
}
