@preconcurrency import CoreNFC
import DossivoixCore

/// Service NFC réel, basé sur `NFCTagReaderSession`, pour la lecture et l'écriture.
///
/// La détection physique permet d'ajouter les puces vierges. Pour les étiquettes
/// NDEF, lecture, règles de remplacement et écriture restent celles du build 7.
///
/// IMPORTANT : rien n'appelle jamais `writeLock` : les étiquettes ne sont jamais verrouillées.
@MainActor
final class CoreNFCTagService: NSObject, TagDiagnosticProviding {
    private let trace = NFCDiagnosticTrace()
    var lastDiagnosticReport: String { trace.report }
    /// Travail à faire quand une étiquette est détectée, et façon de signaler un échec de session.
    private struct Job {
        let operation: Phrases.Operation
        let handle: (NFCTag, NFCTagReaderSession) async -> Void
        let fail: (TagError) -> Void
    }

    private enum SessionControl: Error {
        case rediscoverPreparedTag(Data)
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
        body: @escaping (NFCTag, Bool, @escaping () throws -> Void, @escaping () async throws -> Void) async throws -> (value: Value, sheetMessage: String)
    ) async -> Result<Value, TagError> {
        guard NFCTagReaderSession.readingAvailable else { return .failure(.readingUnavailable) }
        guard session == nil else { return .failure(.systemBusy) }

        trace.reset()
        trace.record("Opération : \(operation)")
        return await withCheckedContinuation { continuation in
            // Le résultat n'est rendu qu'une seule fois, quoi qu'il arrive.
            var isFinished = false
            var preparedIdentifier: Data?
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
                        if let preparedIdentifier {
                            guard case .miFare(let mifare) = tag, mifare.identifier == preparedIdentifier else {
                                throw TagError.differentTag
                            }
                        }
                        try await session.connect(to: tag)
                        try ensureCurrent()
                        let (value, sheetMessage) = try await body(tag, preparedIdentifier != nil, ensureCurrent, {
                            try ensureCurrent()
                            try await session.connect(to: tag)
                            try ensureCurrent()
                        })
                        try ensureCurrent()
                        session.alertMessage = sheetMessage
                        finish(.success(value))
                        session.invalidate()
                    } catch SessionControl.rediscoverPreparedTag(let identifier) {
                        guard !isFinished, session === self?.session else { return }
                        // Une seule redétection, dans la même feuille NFC. La puce préparée
                        // est retenue par son UID pour ne pas écrire sur une autre étiquette.
                        preparedIdentifier = identifier
                        self?.isHandlingTag = false
                        session.restartPolling()
                    } catch {
                        guard !isFinished, session === self?.session else { return }
                        self?.trace.record("Échec : \(error)")
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
        await runSession(operation: .reading, alertMessage: Phrases.nfcSheetApproach) { physicalTag, _, ensureCurrent, _ in
            let tag = try physicalTag.ndefTag
            let (status, _) = try await tag.queryNDEFStatus()
            try ensureCurrent()
            self.trace.record("Statut NDEF CoreNFC : \(status.rawValue)")
            if status == .notSupported {
                let snapshot = try await Type2TagPreparation.inspect(physicalTag, ensureCurrent: ensureCurrent, diagnostic: self.trace.record)
                let records = snapshot.layout.records
                return (records, Phrases.nfcSheetReadDone)
            }
            let records = try await Self.readRecords(of: tag)
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
        var preparedContents: [NDEFRecord]?
        let alertMessage = isSecondPass ? Phrases.nfcSheetApproachAgain : Phrases.nfcSheetApproach
        return await runSession(operation: .writing, alertMessage: alertMessage) { physicalTag, wasPrepared, ensureCurrent, reconnect in
            let tag = try physicalTag.ndefTag
            var (status, capacity) = try await tag.queryNDEFStatus()
            try ensureCurrent()
            self.trace.record("Statut NDEF CoreNFC : \(status.rawValue)")
            if status == .notSupported {
                guard !wasPrepared else { throw TagError.writeFailed }
                // Ajout exclusivement pour une puce que le parcours NDEF ne sait pas traiter.
                let snapshot = try await Type2TagPreparation.inspect(physicalTag, ensureCurrent: ensureCurrent, diagnostic: self.trace.record)
                let existing = snapshot.layout.records
                switch WritePlanner.decide(status: snapshot.layout.isReadOnly ? .readOnly : .readWrite,
                                           capacity: snapshot.layout.maxMessageLength, current: existing,
                                           desired: records, expectedCurrent: expectedCurrent) {
                case .askReplace: return (.needsReplaceConfirmation(current: existing), Phrases.nfcSheetTagInUse)
                case .alreadyUpToDate: return (.alreadyUpToDate, Phrases.nfcSheetAlreadyUpToDate)
                case .refuse(let error): throw error
                case .write: break
                }
                try snapshot.layout.checkCapacity(for: records)
                try await Type2TagPreparation.prepare(physicalTag, snapshot: snapshot, replacingExisting: true, ensureCurrent: ensureCurrent)
                preparedContents = existing
                try await reconnect()
                (status, capacity) = try await tag.queryNDEFStatus()
                try ensureCurrent()
                // L'initialisation a été vérifiée par relecture ; ne pas annoncer une
                // incompatibilité si iOS ne rafraîchit pas encore son cache NDEF.
                if status == .notSupported, case .miFare(let mifare) = physicalTag {
                    throw SessionControl.rediscoverPreparedTag(mifare.identifier)
                }
            }
            try ensureCurrent()
            let nativeCurrent = try await Self.readRecords(of: tag)
            try ensureCurrent()
            if preparedContents != nil, TagDecoder.decode(nativeCurrent).outcome != .empty { throw TagError.differentTag }
            let current = preparedContents ?? nativeCurrent

            switch WritePlanner.decide(
                status: TagWriteStatus(status),
                capacity: capacity,
                current: current,
                desired: records,
                expectedCurrent: expectedCurrent
            ) {
            case .write:
                try ensureCurrent()
                try await tag.writeNDEF(NFCNDEFMessage(records: records.map(NFCNDEFPayload.init)))
                try ensureCurrent()
                // Relecture pour confirmer que l'écriture a bien pris.
                let readBack = try await Self.readRecords(of: tag)
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
