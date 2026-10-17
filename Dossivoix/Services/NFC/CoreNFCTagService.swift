@preconcurrency import CoreNFC
import DossivoixCore

/// Service NFC réel, basé sur `NFCNDEFReaderSession`.
///
/// On utilise la variante « didDetect tags » (et non « didDetectNDEFs ») : elle permet de
/// se connecter à l'étiquette, de connaître son état (compatible, verrouillée, capacité),
/// et servira aussi à l'écriture. Rien n'appelle jamais `writeLock` : les étiquettes
/// ne sont jamais verrouillées.
@MainActor
final class CoreNFCTagService: NSObject, TagReading {
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<Result<[NDEFRecord], TagError>, Never>?

    func readTag() async -> Result<[NDEFRecord], TagError> {
        guard NFCNDEFReaderSession.readingAvailable else { return .failure(.readingUnavailable) }
        guard session == nil else { return .failure(.systemBusy) }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            session.alertMessage = Phrases.nfcSheetApproach
            self.session = session
            session.begin()
        }
    }

    // MARK: - Fin de session

    /// Termine la session avec un succès : la feuille NFC affiche une coche et le message.
    private func succeed(_ records: [NDEFRecord], session: NFCNDEFReaderSession) {
        session.alertMessage = Phrases.nfcSheetReadDone
        session.invalidate()
        complete(with: .success(records))
    }

    /// Termine la session avec une erreur : la feuille NFC affiche le message d'erreur.
    private func fail(_ error: TagError, session: NFCNDEFReaderSession) {
        session.invalidate(errorMessage: Phrases.message(for: error, during: .reading))
        complete(with: .failure(error))
    }

    /// Renvoie le résultat à l'appelant, une seule fois.
    private func complete(with result: Result<[NDEFRecord], TagError>) {
        session = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    /// Lit le contenu NDEF de l'étiquette détectée.
    private func read(_ tag: NFCNDEFTag, in session: NFCNDEFReaderSession) async {
        do {
            try await session.connect(to: tag)
            let (status, _) = try await tag.queryNDEFStatus()
            guard status != .notSupported else {
                fail(.notNDEFCompatible, session: session)
                return
            }
            let message = try await tag.readNDEF()
            succeed(message.records.map(NDEFRecord.init), session: session)
        } catch where error.isZeroLengthNDEFMessage {
            // Étiquette formatée mais sans contenu.
            succeed([], session: session)
        } catch {
            fail(TagError(nfcError: error), session: session)
        }
    }
}

// MARK: - NFCNDEFReaderSessionDelegate
// La session est créée avec la file principale : les rappels arrivent sur le thread principal.

extension CoreNFCTagService: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    /// Obligatoire, mais non utilisé : `didDetect tags` est appelé à la place.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        MainActor.assumeIsolated {
            guard tags.count == 1, let tag = tags.first else {
                // Plusieurs étiquettes en même temps : on demande d'en approcher une seule.
                session.alertMessage = Phrases.nfcSheetSeveralTags
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    session.restartPolling()
                }
                return
            }
            Task { await self.read(tag, in: session) }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        MainActor.assumeIsolated {
            // Appelé aussi après nos propres `invalidate()` : le résultat est alors déjà rendu,
            // et `complete` ne fait plus rien.
            guard session === self.session else { return }
            complete(with: .failure(TagError(nfcError: error)))
        }
    }
}
