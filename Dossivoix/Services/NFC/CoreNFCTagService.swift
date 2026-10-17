@preconcurrency import CoreNFC
import DossivoixCore

/// Service NFC réel, basé sur `NFCNDEFReaderSession`, pour la lecture et l'écriture.
///
/// On utilise la variante « didDetect tags » (et non « didDetectNDEFs ») : elle permet de
/// se connecter à l'étiquette, de connaître son état (compatible, verrouillée, capacité),
/// puis de lire et d'écrire dans la même session.
///
/// IMPORTANT : rien n'appelle jamais `writeLock` : les étiquettes ne sont jamais verrouillées.
@MainActor
final class CoreNFCTagService: NSObject {
    /// Travail à faire quand une étiquette est détectée, et façon de signaler un échec de session.
    private struct Job {
        let operation: Phrases.Operation
        let handle: (NFCNDEFTag, NFCNDEFReaderSession) async -> Void
        let fail: (TagError) -> Void
    }

    private var session: NFCNDEFReaderSession?
    private var job: Job?

    func cancel() {
        session?.invalidate()
        job?.fail(.userCanceled)
    }

    /// Ouvre une session NFC ; `body` s'exécute sur l'étiquette connectée et renvoie
    /// la valeur à rendre ainsi que le message de succès à afficher sur la feuille.
    /// Une `TagError` lancée par `body` termine la session avec le message d'erreur correspondant.
    private func runSession<Value>(
        operation: Phrases.Operation,
        alertMessage: String,
        body: @escaping (NFCNDEFTag) async throws -> (value: Value, sheetMessage: String)
    ) async -> Result<Value, TagError> {
        guard NFCNDEFReaderSession.readingAvailable else { return .failure(.readingUnavailable) }
        guard session == nil else { return .failure(.systemBusy) }

        return await withCheckedContinuation { continuation in
            // Le résultat n'est rendu qu'une seule fois, quoi qu'il arrive.
            var isFinished = false
            let finish: (Result<Value, TagError>) -> Void = { [weak self] result in
                guard !isFinished else { return }
                isFinished = true
                self?.job = nil
                self?.session = nil
                continuation.resume(returning: result)
            }

            job = Job(
                operation: operation,
                handle: { [weak self] tag, session in
                    do {
                        guard session === self?.session else { return }
                        try await session.connect(to: tag)
                        guard session === self?.session else { return }
                        let (value, sheetMessage) = try await body(tag)
                        session.alertMessage = sheetMessage
                        session.invalidate()
                        finish(.success(value))
                    } catch {
                        let tagError = error as? TagError ?? TagError(nfcError: error)
                        session.invalidate(errorMessage: Phrases.message(for: tagError, during: operation))
                        finish(.failure(tagError))
                    }
                },
                fail: { error in finish(.failure(error)) }
            )

            let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            session.alertMessage = alertMessage
            self.session = session
            session.begin()
        }
    }

    /// Contenu NDEF de l'étiquette ; liste vide pour une étiquette sans contenu.
    private static func readRecords(of tag: NFCNDEFTag) async throws -> [NDEFRecord] {
        do {
            return try await tag.readNDEF().records.map(NDEFRecord.init)
        } catch where error.isZeroLengthNDEFMessage {
            return []
        }
    }
}

// MARK: - Lecture

extension CoreNFCTagService: TagReading {
    func readTag() async -> Result<[NDEFRecord], TagError> {
        await runSession(operation: .reading, alertMessage: Phrases.nfcSheetApproach) { tag in
            let (status, _) = try await tag.queryNDEFStatus()
            guard status != .notSupported else { throw TagError.notNDEFCompatible }
            return (try await Self.readRecords(of: tag), Phrases.nfcSheetReadDone)
        }
    }
}

// MARK: - Écriture

extension CoreNFCTagService: TagWriting {
    func writeTag(
        records: [NDEFRecord],
        expectedCurrent: [NDEFRecord]?,
        isSecondPass: Bool
    ) async -> Result<TagWriteOutcome, TagError> {
        let alertMessage = isSecondPass ? Phrases.nfcSheetApproachAgain : Phrases.nfcSheetApproach
        return await runSession(operation: .writing, alertMessage: alertMessage) { tag in
            let (status, capacity) = try await tag.queryNDEFStatus()
            let current = status == .notSupported ? [] : try await Self.readRecords(of: tag)

            switch WritePlanner.decide(
                status: TagWriteStatus(status),
                capacity: capacity,
                current: current,
                desired: records,
                expectedCurrent: expectedCurrent
            ) {
            case .write:
                try await tag.writeNDEF(NFCNDEFMessage(records: records.map(NFCNDEFPayload.init)))
                // Relecture pour confirmer que l'écriture a bien pris.
                let readBack = try await Self.readRecords(of: tag)
                guard WritePlanner.isVerified(readBack: readBack, desired: records) else {
                    throw TagError.writeFailed
                }
                return (.written(previous: current), Phrases.nfcSheetWriteDone)
            case .alreadyUpToDate:
                return (.alreadyUpToDate, Phrases.nfcSheetAlreadyUpToDate)
            case .askReplace:
                return (.needsReplaceConfirmation(current: current), Phrases.nfcSheetTagInUse)
            case .refuse(let error):
                throw error
            }
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
            guard let job else { return }
            Task { await job.handle(tag, session) }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        MainActor.assumeIsolated {
            // Appelé aussi après nos propres `invalidate()` : le résultat est alors déjà rendu.
            guard session === self.session else { return }
            job?.fail(TagError(nfcError: error))
        }
    }
}
