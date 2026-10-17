import Foundation
import Observation
import UIKit
import DossivoixCore

/// Demande d'ouverture de la saisie au clavier (solution de secours).
struct TextEntryRequest: Identifiable, Equatable {
    let id = UUID()
    let prefill: String?
}

/// Chef d'orchestre : exécute les effets décidés par la machine à états (`FlowMachine`)
/// à l'aide des services (NFC, parole, écoute, signaux), et lui renvoie leurs résultats.
///
/// Toute la logique du parcours est dans `FlowMachine` (testée) ; ici, uniquement l'exécution :
/// - les effets s'enchaînent dans l'ordre ; la parole est toujours terminée avant une écoute ;
/// - un nouvel événement (bouton touché…) coupe la parole et l'écoute en cours,
///   et rend caduque la suite de l'ancienne chaîne d'effets.
@MainActor
@Observable
final class FlowCoordinator {
    /// Dernier message, affiché en grand à l'écran et prononcé.
    private(set) var statusMessage = Phrases.welcome
    /// État courant du parcours, pour adapter l'écran.
    private(set) var state: FlowState = .idle
    /// Vrai pendant une écoute (micro ouvert).
    private(set) var isListening = false
    /// Saisie au clavier à ouvrir (modifiable par l'écran).
    var textEntryRequest: TextEntryRequest?

    let diagnostics: DiagnosticLog
    private var machine = FlowMachine()
    /// Numéro de la chaîne d'effets en cours : une chaîne plus ancienne s'arrête d'elle-même.
    private var generation = 0
    private var effectTask: Task<Void, Never>?
    /// Dernier résultat annoncé, réaffiché au retour au repos.
    private var lastResultMessage: String?

    private let tags: TagReading & TagWriting
    private let speech: SpeechOutput
    private let speechInput: SpeechInput
    private let feedback: FeedbackPlaying
    private let audioSession: AudioSessionControlling
    private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        tags: TagReading & TagWriting,
        speech: SpeechOutput,
        speechInput: SpeechInput,
        feedback: FeedbackPlaying,
        audioSession: AudioSessionControlling,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { false },
        diagnostics: DiagnosticLog? = nil
    ) {
        self.tags = tags
        self.speech = speech
        self.speechInput = speechInput
        self.feedback = feedback
        self.audioSession = audioSession
        self.isVoiceOverRunning = isVoiceOverRunning
        self.diagnostics = diagnostics ?? DiagnosticLog()
    }

    /// Coordinateur réel : CoreNFC, synthèse vocale, reconnaissance vocale, sons et vibrations.
    ///
    /// En Debug, pour essayer les parcours dans le simulateur :
    /// - `-FakeNFC` simule les étiquettes (une étiquette SmartVision, puis remplacement accepté) ;
    /// - `-FakeVoice` simule les réponses vocales (« banque », « oui », « oui », puis silence).
    static func live() -> FlowCoordinator {
        let arguments = ProcessInfo.processInfo.arguments
        var tags: TagReading & TagWriting = CoreNFCTagService()
        var speechInput: SpeechInput = SpeechRecognitionInput()
        #if DEBUG
        if arguments.contains("-FakeNFC") {
            let existing = SmartVisionFormat.standard.records(forFolderName: "Dossier panneau solaire")
            tags = FakeTagService(
                readResult: .success(existing),
                writeResults: [
                    .success(.needsReplaceConfirmation(current: existing)),
                    .success(.written(previous: existing)),
                ]
            )
        }
        if arguments.contains("-FakeVoice") {
            speechInput = ScriptedSpeechInput(answers: [.text("banque"), .text("oui"), .text("oui")])
        }
        #endif
        return FlowCoordinator(
            tags: tags,
            speech: AdaptiveSpeechOutput.live(),
            speechInput: speechInput,
            feedback: SoundAndHapticFeedback(),
            audioSession: AudioSessionManager(),
            isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }

    // MARK: - Actions (écran, Siri)

    func startReading() { send(.startReading) }
    func startWriting() { send(.startWriting) }
    func typedName(_ name: String) { send(.typedName(name)) }
    func answer(_ answer: VoiceAnswer) { send(.screenAnswer(answer)) }
    func cancel() { send(.cancel) }

    /// Ouvre la saisie au clavier : la parole et l'écoute en cours s'arrêtent,
    /// et la machine conserve la cible pendant la saisie.
    func openKeyboardEntry(prefill: String? = nil) {
        send(.requestTextEntry(prefill: prefill))
    }

    /// Tout arrêter sans rien dire (app passée en arrière-plan).
    func stopAll() {
        interruptChain()
        machine.reset()
        state = machine.state
        textEntryRequest = nil
        returnToRest()
    }

    // MARK: - Boucle événement → effets

    private func send(_ event: FlowEvent) {
        interruptChain()
        textEntryRequest = nil
        let effects = machine.handle(event)
        state = machine.state
        guard !effects.isEmpty else {
            if state == .idle { returnToRest() }
            return
        }
        let current = generation
        effectTask = Task {
            guard current == generation, !Task.isCancelled else { return }
            // Le clavier seul n'a pas besoin de prendre la session audio.
            if case .enteringName = state, effects.count == 1 {
                await run(effects, generation: current)
                return
            }
            await audioSession.activate()
            await run(effects, generation: current)
        }
    }

    /// Retour au repos : l'écran réaffiche le dernier résultat (nom lu, écrit, erreur…)
    /// plutôt qu'une question restée sans réponse, et l'audio est rendu aux autres apps.
    private func returnToRest() {
        statusMessage = lastResultMessage ?? Phrases.welcome
        audioSession.deactivate()
    }

    /// Coupe la parole et l'écoute en cours ; la chaîne d'effets en cours s'arrêtera.
    private func interruptChain() {
        generation += 1
        effectTask?.cancel()
        effectTask = nil
        isListening = false
        speechInput.cancel()
        speech.stop()
        feedback.stop()
        tags.cancel()
    }

    private func run(_ effects: [FlowEffect], generation current: Int) async {
        for effect in effects {
            guard current == generation, !Task.isCancelled else { return }
            switch effect {
            case .say(let text, let cue):
                await announce(text, cue: cue, generation: current)

            case .recordDiagnostic(let records):
                diagnostics.add(TagDecoder.decode(records))

            case .showTextEntry(let prefill):
                audioSession.deactivate()
                textEntryRequest = TextEntryRequest(prefill: prefill)

            case .listen(let kind):
                await feedback.play(.listening)
                guard current == generation else { return }
                isListening = true
                let result = await speechInput.listen(kind)
                guard current == generation else { return }
                isListening = false
                send(.heard(result))
                return

            case .readTag:
                let result = await withApproachPrompt(Phrases.approachTag, generation: current) {
                    await self.tags.readTag()
                }
                guard current == generation else { return }
                send(.readFinished(result))
                return

            case .writeTag(let records, let expectedCurrent, let isSecondPass):
                let prompt = isSecondPass ? Phrases.approachTagAgain : Phrases.approachTag
                let result = await withApproachPrompt(prompt, generation: current) {
                    await self.tags.writeTag(records: records, expectedCurrent: expectedCurrent,
                                             isSecondPass: isSecondPass)
                }
                guard current == generation else { return }
                send(.writeFinished(result))
                return
            }
        }
        // Fin de parcours : on rend l'audio aux autres apps.
        if current == generation && state == .idle {
            audioSession.deactivate()
        }
    }

    // MARK: - Outils

    /// Prononce la consigne pendant que la feuille NFC s'ouvre, puis la coupe dès que
    /// l'étiquette est traitée (ou que le NFC est indisponible).
    /// Avec VoiceOver, la feuille NFC est déjà lue : la consigne est omise (voir VoiceSettings).
    private func withApproachPrompt<Value>(_ prompt: String, generation current: Int,
                                           _ operation: () async -> Value) async -> Value {
        statusMessage = prompt
        let speaking = Task {
            let skipped = VoiceSettings.skipsApproachPromptWithVoiceOver && isVoiceOverRunning()
            if !skipped && !Task.isCancelled && current == generation {
                await speech.speak(prompt)
            }
        }
        let value = await operation()
        speaking.cancel()
        // Une ancienne session NFC ne doit pas couper la parole du parcours suivant.
        if current == generation { speech.stop() }
        await speaking.value
        return value
    }

    /// Affiche le message, joue le signal éventuel, puis prononce le message.
    /// Un message accompagné d'un signal est un résultat : il est gardé pour le retour au repos.
    private func announce(_ text: String, cue: FeedbackCue?, generation current: Int) async {
        statusMessage = text
        if cue != nil {
            lastResultMessage = text
        }
        if let cue {
            await feedback.play(cue)
        }
        guard current == generation, !Task.isCancelled else { return }
        await speech.speak(text)
    }
}
