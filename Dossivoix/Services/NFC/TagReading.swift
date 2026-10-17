import DossivoixCore

/// Lecture d'une étiquette NFC.
/// Protocole séparé de CoreNFC pour pouvoir simuler le NFC (tests, aperçus SwiftUI).
@MainActor
protocol TagReading: AnyObject {
    /// Ouvre la feuille NFC et renvoie les enregistrements de la première étiquette approchée.
    /// Une étiquette vide renvoie une liste vide (ce n'est pas une erreur).
    func readTag() async -> Result<[NDEFRecord], TagError>
}

/// Lecteur simulé : renvoie toujours le même résultat.
final class FakeTagReader: TagReading {
    var result: Result<[NDEFRecord], TagError>

    init(result: Result<[NDEFRecord], TagError>) {
        self.result = result
    }

    func readTag() async -> Result<[NDEFRecord], TagError> {
        result
    }
}
