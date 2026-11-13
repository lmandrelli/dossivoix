@preconcurrency import CoreNFC
import DossivoixCore

/// Service NFC réel, basé sur `NFCTagReaderSession`, pour la lecture et l'écriture.
///
/// La détection porte sur la puce, même sans message NDEF ni formatage préalable.
/// Les échanges NDEF habituels restent utilisés sur les étiquettes formatées.
///
/// IMPORTANT : rien n'appelle jamais `writeLock` : les étiquettes ne sont jamais verrouillées.
@MainActor
final class CoreNFCTagService: NSObject {
    /// Travail à faire quand une étiquette est détectée, et façon de signaler un échec de session.
    private struct Job {
        let operation: Phrases.Operation
        let handle: (NFCTag, NFCTagReaderSession) async -> Void
        let fail: (TagError) -> Void
    }

    private var session: NFCTagReaderSession?
    private var job: Job?
    private var isHandlingTag = false
    private var isRestartPending = false

    func cancel() {
        let currentSession = session
        job?.fail(.userCanceled)
        currentSession?.invalidate()
    }

    /// Ouvre une session NFC ; `body` s'exécute sur l'étiquette connectée et renvoie
    /// la valeur à rendre ainsi que le message de succès à afficher sur la feuille.
    /// Une `TagError` lancée par `body` termine la session avec le message d'erreur correspondant.
    private func runSession<Value>(
        operation: Phrases.Operation,
        alertMessage: String,
        body: @escaping (NFCTag, @escaping () throws -> Void) async throws -> (value: Value, sheetMessage: String)
    ) async -> Result<Value, TagError> {
        guard NFCTagReaderSession.readingAvailable else { return .failure(.readingUnavailable) }
        guard session == nil else { return .failure(.systemBusy) }

        return await withCheckedContinuation { continuation in
            // Le résultat n'est rendu qu'une seule fois, quoi qu'il arrive.
            var isFinished = false
            let finish: (Result<Value, TagError>) -> Void = { [weak self] result in
                guard !isFinished else { return }
                isFinished = true
                self?.job = nil
                self?.session = nil
                self?.isHandlingTag = false
                self?.isRestartPending = false
                continuation.resume(returning: result)
            }

            job = Job(
                operation: operation,
                handle: { [weak self] tag, session in
                    let ensureCurrent: () throws -> Void = { [weak self] in
                        guard !isFinished, session === self?.session else {
                            throw TagError.userCanceled
                        }
                    }
                    do {
                        try ensureCurrent()
                        try await session.connect(to: tag)
                        try ensureCurrent()
                        let (value, sheetMessage) = try await body(tag, ensureCurrent)
                        try ensureCurrent()
                        session.alertMessage = sheetMessage
                        finish(.success(value))
                        session.invalidate()
                    } catch {
                        guard !isFinished, session === self?.session else { return }
                        let tagError = error as? TagError ?? TagError(nfcError: error)
                        finish(.failure(tagError))
                        session.invalidate(errorMessage: Phrases.message(for: tagError, during: operation))
                    }
                },
                fail: { error in finish(.failure(error)) }
            )

            guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: .main) else {
                finish(.failure(.readingUnavailable))
                return
            }
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
        await runSession(operation: .reading, alertMessage: Phrases.nfcSheetApproach) { tag, ensureCurrent in
            let ndef = try tag.ndefTag
            let (status, _) = try await ndef.queryNDEFStatus()
            try ensureCurrent()
            if status == .notSupported {
                _ = try await Self.inspectBlankNTAG(tag, ensureCurrent: ensureCurrent)
                return ([], Phrases.nfcSheetReadDone)
            }
            let records = try await Self.readRecords(of: ndef)
            try ensureCurrent()
            return (records, Phrases.nfcSheetReadDone)
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
        return await runSession(operation: .writing, alertMessage: alertMessage) { tag, ensureCurrent in
            let ndef = try tag.ndefTag
            let (status, capacity) = try await ndef.queryNDEFStatus()
            try ensureCurrent()
            if status == .notSupported {
                let blank = try await Self.inspectBlankNTAG(tag, ensureCurrent: ensureCurrent)
                guard expectedCurrent == nil || expectedCurrent == [] else { throw TagError.differentTag }
                try await Self.writeBlankNTAG(tag, blank: blank, records: records, ensureCurrent: ensureCurrent)
                return (.written(previous: []), Phrases.nfcSheetWriteDone)
            }
            let current = try await Self.readRecords(of: ndef)
            try ensureCurrent()

            switch WritePlanner.decide(
                status: TagWriteStatus(status),
                capacity: capacity,
                current: current,
                desired: records,
                expectedCurrent: expectedCurrent
            ) {
            case .write:
                try ensureCurrent()
                try await ndef.writeNDEF(NFCNDEFMessage(records: records.map(NFCNDEFPayload.init)))
                try ensureCurrent()
                // Relecture pour confirmer que l'écriture a bien pris.
                let readBack = try await Self.readRecords(of: ndef)
                try ensureCurrent()
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

// MARK: - NFCTagReaderSessionDelegate
// La session est créée avec la file principale : les rappels arrivent sur le thread principal.

extension CoreNFCTagService: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            guard session === self.session, !isHandlingTag else { return }
            guard tags.count == 1, let tag = tags.first else {
                // Plusieurs étiquettes en même temps : on demande d'en approcher une seule.
                guard !isRestartPending else { return }
                isRestartPending = true
                session.alertMessage = Phrases.nfcSheetSeveralTags
                Task {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    guard session === self.session, !self.isHandlingTag, !Task.isCancelled else { return }
                    self.isRestartPending = false
                    session.restartPolling()
                }
                return
            }
            guard let job else { return }
            isHandlingTag = true
            Task { await job.handle(tag, session) }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        MainActor.assumeIsolated {
            // Appelé aussi après nos propres `invalidate()` : le résultat est alors déjà rendu.
            guard session === self.session else { return }
            job?.fail(TagError(nfcError: error))
        }
    }
}
