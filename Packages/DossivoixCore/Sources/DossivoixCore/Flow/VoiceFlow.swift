import Foundation

// MARK: - Écoute

/// Type d'écoute : dictée d'un nom, ou réponse courte.
public enum ListenKind: Equatable, Sendable {
    case name
    case answer

    /// Délais en secondes : la dictée tolère 30 secondes sans nouvelle transcription.
    public var timing: ListenTiming {
        switch self {
        case .name: ListenTiming(initialTimeout: 30, silenceTimeout: 30, maxDuration: 55)
        case .answer: ListenTiming(initialTimeout: 5, silenceTimeout: 1.0, maxDuration: 6)
        }
    }
}

public struct ListenTiming: Equatable, Sendable {
    /// Délai pour commencer à parler ; au-delà, l'écoute s'arrête sans résultat.
    public let initialTimeout: Double
    /// Silence après la dernière parole qui marque la fin de la réponse.
    public let silenceTimeout: Double
    /// Durée maximale de l'écoute.
    public let maxDuration: Double

    public init(initialTimeout: Double, silenceTimeout: Double, maxDuration: Double) {
        self.initialTimeout = initialTimeout
        self.silenceTimeout = silenceTimeout
        self.maxDuration = maxDuration
    }
}

/// Ce qu'une écoute a donné.
public enum ListenResult: Equatable, Sendable {
    case text(String)
    /// Contenu terminé explicitement, sans réinterprétation des mots littéraux.
    case dictated(String)
    /// Rien d'exploitable n'a été entendu dans le délai.
    case silence
    /// Session interrompue ou arrivée à sa limite, sans validation du contenu.
    case paused(String)
    /// « Annuler la dictée » : arrêter la voix en gardant le texte déjà dicté.
    case stopped(String)
    /// Micro ou reconnaissance vocale non autorisés ou indisponibles.
    case unavailable
}

// MARK: - États, événements, effets

/// Étiquette visée par une écriture.
public enum WriteTarget: Equatable, Sendable {
    /// N'importe quelle étiquette : 1er passage (confirmation demandée si elle contient déjà autre chose).
    case anyTag
    /// Contenu déjà connu : renommage ou 2e passage. Ce n'est pas un identifiant matériel.
    case knownTag(expected: [NDEFRecord], isSecondPass: Bool)
}

/// États du parcours. La voix (parole, micro) est indépendante de l'état :
/// l'arrêter ne change que la dictée en cours, mise en pause avec son texte.
public enum FlowState: Equatable, Sendable {
    case idle
    /// Session NFC de lecture en cours.
    case reading
    /// Voix au repos : écoute courte de « lire » ou « écrire ». `lastRead` permet le renommage.
    case voiceMenu(lastRead: [NDEFRecord]?)
    /// Dictée du nom (`attempt` : numéro de l'essai).
    case askingName(attempt: Int, target: WriteTarget)
    /// Voix arrêtée ou session terminée sans commande : brouillon conservé, reprise explicite.
    case pausedDictation(text: String, target: WriteTarget)
    /// « J'ai compris : … C'est bon ? ». Rien n'est écrit sans « oui » ou « C'est bon ».
    case confirmingName(name: String, attempt: Int, target: WriteTarget)
    /// Session NFC d'écriture en cours.
    case writing(name: String, target: WriteTarget)
    /// L'étiquette contient déjà autre chose : « Remplacer ? ». Au-delà des essais, plus d'écoute :
    /// seuls les boutons de l'écran restent possibles.
    case confirmingReplace(name: String, seen: [NDEFRecord], attempt: Int)

    /// Vrai pendant une session NFC : la feuille système d'iOS a la main.
    public var isUsingTag: Bool {
        switch self {
        case .reading, .writing: true
        default: false
        }
    }
}

/// Événements reçus par la machine : actions de l'utilisatrice et résultats des services.
public enum FlowEvent: Equatable, Sendable {
    case startReading
    case startWriting
    /// Bouton Voix : répète la question du contexte et écoute.
    case resumeVoice
    /// Arrêt de la voix (bouton, interruption, arrière-plan) : rien n'est effacé ni validé.
    /// `partial` : transcription déjà reçue par l'écoute coupée.
    case stopVoice(partial: String)
    /// Bouton Terminer quand le micro n'écoute pas : relit le brouillon avant confirmation.
    case finishDictation(partial: String)
    /// Bouton Abandonner : efface le brouillon, aucune étiquette n'est écrite.
    case abandonWriting
    case readFinished(Result<[NDEFRecord], TagError>)
    case writeFinished(Result<TagWriteOutcome, TagError>)
    case heard(ListenResult)
    /// Réponse donnée avec un bouton de l'écran plutôt qu'à la voix.
    case screenAnswer(VoiceAnswer)
}

/// Actions à exécuter par l'app, dans l'ordre. Au plus un effet « qui attend un résultat »
/// (écoute, lecture, écriture), toujours en dernier : son résultat revient comme événement.
public enum FlowEffect: Equatable, Sendable {
    /// Afficher et prononcer un message, précédé d'un signal éventuel.
    case say(String, cue: FeedbackCue?)
    /// Signal « j'écoute », puis écoute.
    case listen(ListenKind)
    case readTag
    case writeTag(records: [NDEFRecord], expectedCurrent: [NDEFRecord]?, isSecondPass: Bool)
    /// Garder ce contenu pour l'écran Diagnostic.
    case recordDiagnostic([NDEFRecord])
}

// MARK: - Machine

/// Machine à états du parcours vocal : logique pure, sans son, sans NFC, sans écran.
/// Chaque événement fait passer d'un état à l'autre et produit la liste des effets à exécuter.
public struct FlowMachine: Sendable {
    /// Nombre d'essais de dictée ou de réponse avant de renvoyer vers l'écran.
    public static let maxAttempts = 2

    public private(set) var state: FlowState = .idle
    private var draft = ""
    private var lastRead: [NDEFRecord]?
    public var dictationDraft: String { draft }
    public let format: SmartVisionFormat

    public init(format: SmartVisionFormat = .standard) {
        self.format = format
    }

    /// Retour au repos sans rien dire (session NFC interrompue, par exemple).
    public mutating func reset() {
        state = .idle
        draft = ""
    }

    /// Vrai si ce nom tient sur l'étiquette au format courant.
    public func fits(_ name: String) -> Bool {
        CapacityCheck(folderName: name, format: format).fits
    }

    public mutating func handle(_ event: FlowEvent) -> [FlowEffect] {
        switch event {
        case .resumeVoice:
            return resumeVoice()

        case .startReading:
            // Un autre parcours commence : aucun brouillon caché ne doit survivre au repos.
            draft = ""
            state = .reading
            return [.readTag]

        case .startWriting:
            lastRead = nil
            return askName(target: .anyTag, intro: Phrases.askName)

        case .stopVoice(let partial):
            stopVoice(partial: partial)
            return []

        case .finishDictation(let partial):
            return finishDictation(partial: partial)

        case .abandonWriting:
            switch state {
            case .askingName, .pausedDictation, .confirmingName:
                draft = ""
                state = .idle
                return [.say(Phrases.writeCanceled, cue: nil)]
            case .confirmingReplace:
                draft = ""
                state = .idle
                return [.say(Phrases.writeCanceledTagUnchanged, cue: nil)]
            default:
                return []
            }

        case .readFinished(let result):
            guard state == .reading else { return [] }
            return readFinished(result)

        case .writeFinished(let result):
            guard case .writing(let name, let target) = state else { return [] }
            return writeFinished(result, name: name, target: target)

        case .heard(let result):
            if case .askingName(let attempt, let target) = state {
                return heardName(result, attempt: attempt, target: target)
            }
            switch result {
            case .text(let text): return answered(VoiceAnswerParser.parse(text), micAvailable: true)
            case .stopped: return answered(.cancel, micAvailable: true)
            case .silence: return answered(nil, micAvailable: true)
            case .unavailable: return answered(nil, micAvailable: false)
            case .paused, .dictated: return []
            }

        case .screenAnswer(let answer):
            return answered(answer, micAvailable: true)
        }
    }

    // MARK: Voix

    /// Arrêter la voix ne détruit rien : la dictée passe en pause avec son texte,
    /// les questions restent affichées avec leurs boutons, le menu vocal se referme.
    private mutating func stopVoice(partial: String) {
        switch state {
        case .askingName(_, let target):
            appendToDraft(partial)
            state = .pausedDictation(text: draft, target: target)
        case .voiceMenu:
            state = .idle
        default:
            break
        }
    }

    private mutating func resumeVoice() -> [FlowEffect] {
        switch state {
        case .reading, .writing: return []
        case .confirmingName(let name, _, let target):
            state = .confirmingName(name: name, attempt: 1, target: target)
            return [.say(Phrases.confirmName(name), cue: nil), .listen(.answer)]
        case .confirmingReplace(let name, let seen, _):
            state = .confirmingReplace(name: name, seen: seen, attempt: 1)
            return [.say(Phrases.askReplace(existing: TagDecoder.decode(seen), newName: name), cue: nil), .listen(.answer)]
        case .pausedDictation(_, let target), .askingName(_, let target):
            state = .askingName(attempt: 1, target: target)
            return [.say(draft.isEmpty ? Phrases.askName : Phrases.resumeDictation, cue: nil), .listen(.name)]
        case .idle, .voiceMenu:
            state = .voiceMenu(lastRead: lastRead)
            return [.say(Phrases.voiceMenu, cue: nil), .listen(.answer)]
        }
    }

    private mutating func appendToDraft(_ text: String) {
        draft = [draft, text].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Lecture

    private mutating func readFinished(_ result: Result<[NDEFRecord], TagError>) -> [FlowEffect] {
        state = .idle
        lastRead = nil
        switch result {
        case .success(let records):
            lastRead = records
            let decoded = TagDecoder.decode(records)
            return [.recordDiagnostic(records),
                    .say(Phrases.readResult(decoded), cue: decoded.folderName == nil ? .error : .success)]
        case .failure(let error):
            return [.say(Phrases.message(for: error, during: .reading), cue: error == .userCanceled ? nil : .error)]
        }
    }

    // MARK: Dictée du nom

    private mutating func askName(target: WriteTarget, intro: String) -> [FlowEffect] {
        draft = ""
        state = .askingName(attempt: 1, target: target)
        return [.say(intro, cue: nil), .listen(.name)]
    }

    private mutating func confirm(_ name: String, target: WriteTarget) -> [FlowEffect] {
        draft = ""
        state = .confirmingName(name: name, attempt: 1, target: target)
        return [.say(Phrases.confirmName(name), cue: nil), .listen(.answer)]
    }

    private mutating func finishDictation(partial: String) -> [FlowEffect] {
        switch state {
        case .askingName(_, let target), .pausedDictation(_, let target):
            appendToDraft(partial)
            let name = FolderName.preparedForWriting(draft)
            guard !name.isEmpty else {
                state = .pausedDictation(text: draft, target: target)
                return [.say(Phrases.didNotHearName, cue: nil)]
            }
            return confirm(name, target: target)
        default:
            return []
        }
    }

    private mutating func heardName(_ result: ListenResult, attempt: Int, target: WriteTarget) -> [FlowEffect] {
        switch result {
        case .text(let text) where VoiceAnswerParser.isStandaloneCancel(text):
            return heardName(.stopped(""), attempt: attempt, target: target)
        case .stopped(let text):
            // « Annuler » arrête seulement la voix : le texte reste, rien n'est validé.
            appendToDraft(text)
            state = .pausedDictation(text: draft, target: target)
            return [.say(Phrases.voiceStoppedDraftKept, cue: nil)]
        case .paused(let text):
            appendToDraft(text)
            guard !draft.isEmpty else {
                state = .pausedDictation(text: "", target: target)
                return [.say(Phrases.didNotHearName, cue: nil)]
            }
            // Arrêt automatique : relecture, jamais d'écriture sans confirmation.
            return confirm(FolderName.preparedForWriting(draft), target: target)
        case .text(let text), .dictated(let text):
            appendToDraft(text)
            let name = FolderName.preparedForWriting(draft)
            guard !name.isEmpty else {
                return heardName(.silence, attempt: attempt, target: target)
            }
            return confirm(name, target: target)
        case .unavailable:
            state = .pausedDictation(text: draft, target: target)
            return [.say(Phrases.voiceUnavailable, cue: .error)]
        case .silence:
            guard attempt < Self.maxAttempts else {
                state = .pausedDictation(text: draft, target: target)
                return [.say(Phrases.didNotHearName, cue: .error)]
            }
            state = .askingName(attempt: attempt + 1, target: target)
            return [.say(Phrases.didNotHearNameRetry, cue: nil), .listen(.name)]
        }
    }

    // MARK: Réponses courtes

    private mutating func answered(_ answer: VoiceAnswer?, micAvailable: Bool) -> [FlowEffect] {
        switch state {
        case .voiceMenu(let lastRead):
            switch answer {
            case .again:
                state = .reading
                return [.readTag]
            case .write:
                return rename(lastRead)
            default:
                // Pas de réponse claire, ou « annuler » : retour au repos, sans rien dire.
                state = .idle
                return []
            }

        case .confirmingName(let name, let attempt, let target):
            switch answer {
            case .again:
                // « encore » / « continuer » : ajouter un segment après une coupure trop tôt.
                draft = name
                state = .askingName(attempt: 1, target: target)
                return [.say(Phrases.resumeDictation, cue: nil), .listen(.name)]
            case .yes:
                return write(name, target: target)
            case .no, .restart:
                return askName(target: target, intro: Phrases.askNameAgain)
            case .cancel:
                // La question et ses boutons restent : seule la voix s'arrête.
                return [.say(Phrases.voiceStopped, cue: nil)]
            default:
                guard micAvailable, attempt < Self.maxAttempts else {
                    state = .confirmingName(name: name, attempt: Self.maxAttempts + 1, target: target)
                    let message = micAvailable ? Phrases.useScreen : Phrases.voiceUnavailable
                    return [.say(message, cue: .error)]
                }
                state = .confirmingName(name: name, attempt: attempt + 1, target: target)
                return [.say(Phrases.didNotUnderstandYesNo + " " + Phrases.confirmName(name), cue: nil),
                        .listen(.answer)]
            }

        case .confirmingReplace(let name, let seen, let attempt):
            switch answer {
            case .yes:
                return write(name, target: .knownTag(expected: seen, isSecondPass: true))
            case .no:
                state = .idle
                return [.say(Phrases.writeCanceledTagUnchanged, cue: nil)]
            case .cancel:
                return [.say(Phrases.voiceStopped, cue: nil)]
            case .restart:
                return askName(target: .anyTag, intro: Phrases.askNameAgain)
            default:
                guard attempt <= Self.maxAttempts else { return [] } // Déjà renvoyée vers l'écran.
                guard micAvailable, attempt < Self.maxAttempts else {
                    // Plus d'écoute : l'état reste, les boutons Remplacer / Garder restent affichés.
                    state = .confirmingReplace(name: name, seen: seen, attempt: Self.maxAttempts + 1)
                    return [.say(micAvailable ? Phrases.useScreenButtons : Phrases.voiceUnavailable, cue: .error)]
                }
                state = .confirmingReplace(name: name, seen: seen, attempt: attempt + 1)
                return [.say(Phrases.didNotUnderstandReplace, cue: nil), .listen(.answer)]
            }

        case .idle, .reading, .askingName, .pausedDictation, .writing:
            return []
        }
    }

    // MARK: Écriture

    /// Renommer l'étiquette qui vient d'être lue : pas de nouvelle demande de remplacement,
    /// mais l'écriture vérifie que le contenu est toujours identique.
    /// Deux étiquettes au contenu identique ne peuvent pas être distinguées.
    private mutating func rename(_ lastRead: [NDEFRecord]?) -> [FlowEffect] {
        guard let lastRead else {
            return askName(target: .anyTag, intro: Phrases.askName)
        }
        let intro = TagDecoder.decode(lastRead).folderName.map(Phrases.askNewName(for:)) ?? Phrases.askName
        return askName(target: .knownTag(expected: lastRead, isSecondPass: false), intro: intro)
    }

    /// Lance l'écriture si le nom tient sur une NTAG 213 ; sinon demande un nom plus court.
    private mutating func write(_ name: String, target: WriteTarget) -> [FlowEffect] {
        let check = CapacityCheck(folderName: name, format: format)
        guard check.fits else {
            state = .confirmingName(name: name, attempt: 1, target: target)
            return [.say(Phrases.nameTooLong(check) + " " + Phrases.shortenOrEdit, cue: .error), .listen(.answer)]
        }
        // Confirmer un nom ne vaut pas consentement à supprimer un contenu inconnu.
        if case .knownTag(let expected, false) = target {
            let existing = TagDecoder.decode(expected)
            if existing.hasUnrecognizedParts || existing.outcome == .unrecognized {
                state = .confirmingReplace(name: name, seen: expected, attempt: 1)
                return [.say(Phrases.askReplace(existing: existing, newName: name), cue: nil),
                        .listen(.answer)]
            }
        }
        state = .writing(name: name, target: target)
        switch target {
        case .anyTag:
            return [.writeTag(records: format.records(forFolderName: name), expectedCurrent: nil, isSecondPass: false)]
        case .knownTag(let expected, let isSecondPass):
            return [.writeTag(records: format.records(forFolderName: name),
                              expectedCurrent: expected, isSecondPass: isSecondPass)]
        }
    }

    private mutating func writeFinished(
        _ result: Result<TagWriteOutcome, TagError>,
        name: String,
        target: WriteTarget
    ) -> [FlowEffect] {
        switch result {
        case .success(.written):
            state = .idle
            return [.say(Phrases.written(name), cue: .success)]
        case .success(.alreadyUpToDate):
            state = .idle
            return [.say(Phrases.alreadyWritten(name), cue: .success)]
        case .success(.needsReplaceConfirmation(let current)):
            let existing = TagDecoder.decode(current)
            state = .confirmingReplace(name: name, seen: current, attempt: 1)
            return [.recordDiagnostic(current), .say(Phrases.askReplace(existing: existing, newName: name), cue: nil),
                    .listen(.answer)]
        case .failure(.userCanceled):
            state = .idle
            return [.say(Phrases.writeCanceledCheckTag, cue: nil)]
        case .failure(.readingUnavailable):
            state = .idle
            return [.say(Phrases.message(for: .readingUnavailable, during: .writing), cue: .error)]
        case .failure(.insufficientCapacity):
            state = .confirmingName(name: name, attempt: 1, target: target)
            return [.say(Phrases.message(for: .insufficientCapacity(maxMessageLength: 0), during: .writing)
                         + " " + Phrases.shortenOrEdit, cue: .error),
                    .listen(.answer)]
        case .failure(let error):
            state = .idle
            return [.say(Phrases.message(for: error, during: .writing), cue: .error)]
        }
    }
}
