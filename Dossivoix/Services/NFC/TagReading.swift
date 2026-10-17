import DossivoixCore

/// Lecture d'une étiquette NFC.
/// Protocole séparé de CoreNFC pour pouvoir simuler le NFC (tests, aperçus SwiftUI).
@MainActor
protocol TagReading: AnyObject {
    /// Ouvre la feuille NFC et renvoie les enregistrements de la première étiquette approchée.
    /// Une étiquette vide renvoie une liste vide (ce n'est pas une erreur).
    func readTag() async -> Result<[NDEFRecord], TagError>
}

/// Écriture d'une étiquette NFC. Ne verrouille jamais l'étiquette.
@MainActor
protocol TagWriting: AnyObject {
    /// - Parameters:
    ///   - records: contenu à écrire.
    ///   - expectedCurrent: nil au 1er passage ; au 2e passage, le contenu vu au 1er
    ///     (l'écriture n'a lieu que si l'étiquette le contient toujours).
    ///   - isSecondPass: adapte le texte de la feuille NFC.
    func writeTag(
        records: [NDEFRecord],
        expectedCurrent: [NDEFRecord]?,
        isSecondPass: Bool
    ) async -> Result<TagWriteOutcome, TagError>
}

/// Lecteur et graveur simulés : résultats fixés à l'avance.
final class FakeTagService: TagReading, TagWriting {
    var readResult: Result<[NDEFRecord], TagError>
    var writeResults: [Result<TagWriteOutcome, TagError>]

    init(
        readResult: Result<[NDEFRecord], TagError> = .success([]),
        writeResults: [Result<TagWriteOutcome, TagError>] = []
    ) {
        self.readResult = readResult
        self.writeResults = writeResults
    }

    func readTag() async -> Result<[NDEFRecord], TagError> {
        readResult
    }

    func writeTag(
        records: [NDEFRecord],
        expectedCurrent: [NDEFRecord]?,
        isSecondPass: Bool
    ) async -> Result<TagWriteOutcome, TagError> {
        writeResults.isEmpty ? .failure(.readingUnavailable) : writeResults.removeFirst()
    }
}
