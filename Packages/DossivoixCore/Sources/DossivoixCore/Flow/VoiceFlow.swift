import Foundation

// MARK: - Écoute

/// Type d'écoute : dictée d'un nom, ou réponse courte.
public enum ListenKind: Equatable, Sendable {
    case name
    case answer

    /// Délais d'écoute, en secondes. Pas d'écoute permanente : chaque écoute est courte.
    public var timing: ListenTiming {
        switch self {
        case .name: ListenTiming(initialTimeout: 6, silenceTimeout: 1.5, maxDuration: 15)
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
}

/// Ce qu'une écoute a donné.
public enum ListenResult: Equatable, Sendable {
    case text(String)
    /// Rien d'exploitable n'a été entendu dans le délai.
    case silence
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

/// États du parcours vocal.
public enum FlowState: Equatable, Sendable {
    case idle
    /// Session NFC de lecture en cours.
    case reading
    /// Après une lecture : écoute courte de « encore » ou « écrire ». `lastRead` permet le renommage.
    case offeringAfterRead(lastRead: [NDEFRecord]?)
    /// Dictée du nom (`attempt` : numéro de l'essai).
    case askingName(attempt: Int, target: WriteTarget)
    /// Saisie au clavier, avec conservation de la cible du renommage/remplacement.
    case enteringName(target: WriteTarget)
    /// « J'ai compris : … C'est bon ? »
    case confirmingName(name: String, attempt: Int, target: WriteTarget)
    /// Session NFC d'écriture en cours.
    case writing(name: String, target: WriteTarget)
    /// L'étiquette contient déjà autre chose : « Remplacer ? ». Au-delà des essais, plus d'écoute :
    /// seuls les boutons de l'écran restent possibles.
    case confirmingReplace(name: String, seen: [NDEFRecord], attempt: Int)
    /// Après un échec d'écriture : « encore » pour réessayer.
    case offeringRetry(name: String, target: WriteTarget)
    /// Après une écriture réussie : « oui » pour écrire une autre étiquette.
    case offeringAnotherWrite
}

/// Événements reçus par la machine : actions de l'utilisatrice et résultats des services.
public enum FlowEvent: Equatable, Sendable {
    case startReading
    case startWriting
    /// Nom saisi au clavier (pas de confirmation orale : il est déjà écrit).
    case typedName(String)
    case requestTextEntry(prefill: String?)
    /// Bouton « Annuler » de l'écran.
    case cancel
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
    /// Ouvrir la saisie au clavier (solution de secours), avec un nom pré-rempli éventuel.
    case showTextEntry(prefill: String?)
}

// MARK: - Machine

/// Machine à états du parcours vocal : logique pure, sans son, sans NFC, sans écran.
/// Chaque événement fait passer d'un état à l'autre et produit la liste des effets à exécuter.
public struct FlowMachine: Sendable {
    /// Nombre d'essais de dictée ou de réponse avant de renvoyer vers l'écran.
    public static let maxAttempts = 2

    public private(set) var state: FlowState = .idle
    public let format: SmartVisionFormat

    public init(format: SmartVisionFormat = .standard) {
        self.format = format
    }

    /// Retour au repos sans rien dire (app passée en arrière-plan, par exemple).
    public mutating func reset() {
        state = .idle
    }

    public mutating func handle(_ event: FlowEvent) -> [FlowEffect] {
        switch event {
        case .startReading:
            state = .reading
            return [.readTag]

        case .startWriting:
            return askName(target: .anyTag, intro: Phrases.askName)

        case .typedName(let raw):
            let name = FolderName.preparedForWriting(raw)
            guard !name.isEmpty else { return [] }
            return write(name, target: currentWriteTarget)

        case .requestTextEntry(let prefill):
            state = .enteringName(target: currentWriteTarget)
            return [.showTextEntry(prefill: prefill)]

        case .cancel:
            guard state != .idle else { return [] }
            state = .idle
            return [.say(Phrases.stopped, cue: nil)]

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
            case .silence: return answered(nil, micAvailable: true)
            case .unavailable: return answered(nil, micAvailable: false)
            }

        case .screenAnswer(let answer):
            return answered(answer, micAvailable: true)
        }
    }

    // MARK: Lecture

    private mutating func readFinished(_ result: Result<[NDEFRecord], TagError>) -> [FlowEffect] {
        switch result {
        case .success(let records):
            let decoded = TagDecoder.decode(records)
            state = .offeringAfterRead(lastRead: records)
            return [
                .recordDiagnostic(records),
                .say(Phrases.readResult(decoded), cue: decoded.folderName == nil ? .error : .success),
                .say(Phrases.offerAfterRead, cue: nil),
                .listen(.answer),
            ]
        case .failure(.userCanceled):
            state = .idle
            return [.say(Phrases.message(for: .userCanceled, during: .reading), cue: nil)]
        case .failure(.readingUnavailable):
            state = .idle
            return [.say(Phrases.message(for: .readingUnavailable, during: .reading), cue: .error)]
        case .failure(let error):
            state = .offeringAfterRead(lastRead: nil)
            return [
                .say(Phrases.message(for: error, during: .reading), cue: .error),
                .say(Phrases.offerAfterRead, cue: nil),
                .listen(.answer),
            ]
        }
    }

    // MARK: Dictée du nom

    private mutating func askName(target: WriteTarget, intro: String) -> [FlowEffect] {
        state = .askingName(attempt: 1, target: target)
        return [.say(intro, cue: nil), .listen(.name)]
    }

    private mutating func heardName(_ result: ListenResult, attempt: Int, target: WriteTarget) -> [FlowEffect] {
        switch result {
        case .text(let text) where VoiceAnswerParser.isStandaloneCancel(text):
            state = .idle
            return [.say(Phrases.writeCanceled, cue: nil)]
        case .text(let text) where !FolderName.preparedForWriting(text).isEmpty:
            let name = FolderName.preparedForWriting(text)
            state = .confirmingName(name: name, attempt: 1, target: target)
            return [.say(Phrases.confirmName(name), cue: nil), .listen(.answer)]
        case .unavailable:
            state = .enteringName(target: target)
            return [.say(Phrases.voiceUnavailable, cue: .error), .showTextEntry(prefill: nil)]
        case .text, .silence:
            guard attempt < Self.maxAttempts else {
                state = .enteringName(target: target)
                return [.say(Phrases.useScreen, cue: .error), .showTextEntry(prefill: nil)]
            }
            state = .askingName(attempt: attempt + 1, target: target)
            return [.say(Phrases.didNotHearName, cue: nil), .listen(.name)]
        }
    }

    // MARK: Réponses courtes

    private mutating func answered(_ answer: VoiceAnswer?, micAvailable: Bool) -> [FlowEffect] {
        switch state {
        case .offeringAfterRead(let lastRead):
            switch answer {
            case .again:
                state = .reading
                return [.readTag]
            case .write:
                return rename(lastRead)
            default:
                // Pas de réponse claire : on ne fait rien de plus.
                state = .idle
                return []
            }

        case .confirmingName(let name, let attempt, let target):
            switch answer {
            case .yes:
                return write(name, target: target)
            case .no, .restart:
                return askName(target: target, intro: Phrases.askNameAgain)
            case .cancel:
                state = .idle
                return [.say(Phrases.writeCanceled, cue: nil)]
            default:
                guard micAvailable, attempt < Self.maxAttempts else {
                    state = .enteringName(target: target)
                    let message = micAvailable ? Phrases.useScreen : Phrases.voiceUnavailable
                    return [.say(message, cue: .error), .showTextEntry(prefill: name)]
                }
                state = .confirmingName(name: name, attempt: attempt + 1, target: target)
                return [.say(Phrases.didNotUnderstandYesNo + " " + Phrases.confirmName(name), cue: nil),
                        .listen(.answer)]
            }

        case .confirmingReplace(let name, let seen, let attempt):
            switch answer {
            case .yes:
                return write(name, target: .knownTag(expected: seen, isSecondPass: true))
            case .no, .cancel:
                state = .idle
                return [.say(Phrases.writeCanceledTagUnchanged, cue: nil)]
            case .restart:
                return askName(target: .anyTag, intro: Phrases.askNameAgain)
            default:
                guard attempt <= Self.maxAttempts else { return [] } // Déjà renvoyée vers l'écran.
                guard micAvailable, attempt < Self.maxAttempts else {
                    // Plus d'écoute : l'état reste, les boutons Remplacer / Annuler restent affichés.
                    state = .confirmingReplace(name: name, seen: seen, attempt: Self.maxAttempts + 1)
                    return [.say(micAvailable ? Phrases.useScreenButtons : Phrases.voiceUnavailable, cue: .error)]
                }
                state = .confirmingReplace(name: name, seen: seen, attempt: attempt + 1)
                return [.say(Phrases.didNotUnderstandReplace, cue: nil), .listen(.answer)]
            }

        case .offeringAnotherWrite:
            switch answer {
            case .yes, .again, .write:
                return askName(target: .anyTag, intro: Phrases.askName)
            default:
                state = .idle
                return []
            }

        case .offeringRetry(let name, let target):
            switch answer {
            case .yes, .again, .restart:
                return write(name, target: target)
            default:
                state = .idle
                return []
            }

        case .idle, .reading, .askingName, .enteringName, .writing:
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
            state = .askingName(attempt: 1, target: target)
            return [.say(Phrases.nameTooLong(check) + " " + Phrases.askShorterName, cue: .error), .listen(.name)]
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
            state = .offeringAnotherWrite
            return [.say(Phrases.written(name), cue: .success), .say(Phrases.offerAnotherWrite, cue: nil),
                    .listen(.answer)]
        case .success(.alreadyUpToDate):
            state = .offeringAnotherWrite
            return [.say(Phrases.alreadyWritten(name), cue: .success), .say(Phrases.offerAnotherWrite, cue: nil),
                    .listen(.answer)]
        case .success(.needsReplaceConfirmation(let current)):
            let existing = TagDecoder.decode(current)
            state = .confirmingReplace(name: name, seen: current, attempt: 1)
            return [.recordDiagnostic(current), .say(Phrases.askReplace(existing: existing, newName: name), cue: nil),
                    .listen(.answer)]
        case .failure(.userCanceled):
            state = .idle
            return [.say(Phrases.writeCanceledTagUnchanged, cue: nil)]
        case .failure(.readingUnavailable):
            state = .idle
            return [.say(Phrases.message(for: .readingUnavailable, during: .writing), cue: .error)]
        case .failure(.insufficientCapacity):
            state = .askingName(attempt: 1, target: target)
            return [.say(Phrases.message(for: .insufficientCapacity(maxMessageLength: 0), during: .writing)
                         + " " + Phrases.askShorterName, cue: .error),
                    .listen(.name)]
        case .failure(let error):
            state = .offeringRetry(name: name, target: target)
            return [.say(Phrases.message(for: error, during: .writing), cue: .error), .say(Phrases.offerRetry, cue: nil),
                    .listen(.answer)]
        }
    }

    /// Cible d'écriture en cours (pour un nom saisi au clavier pendant un parcours).
    private var currentWriteTarget: WriteTarget {
        switch state {
        case .askingName(_, let target), .confirmingName(_, _, let target),
             .enteringName(let target), .offeringRetry(_, let target):
            return target
        case .confirmingReplace(_, let seen, _):
            return .knownTag(expected: seen, isSecondPass: true)
        default:
            return .anyTag
        }
    }
}
