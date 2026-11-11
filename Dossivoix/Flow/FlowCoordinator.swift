import Foundation
import Observation
import UIKit
import AVFoundation
import DossivoixCore

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
    /// Parole ou micro en cours, indépendamment de l'état du parcours.
    private(set) var voiceActivity: VoiceActivity = .off
    /// Vrai pendant une écoute (micro ouvert).
    var isListening: Bool { voiceActivity == .listening }
    /// Les trois boutons de l'écran, calculés par la logique testée de `FlowMachine`.
    var controls: ScreenControls { machine.controls(voice: voiceActivity) }

    let diagnostics: DiagnosticLog
    private var machine = FlowMachine()
    private var interruptionObserver: NSObjectProtocol?
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
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.stopAll() }
        }
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

    isolated deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    // MARK: - Actions (écran, Siri)

    func startReading() { send(.startReading) }
    func startWriting() { send(.startWriting) }

    /// Seul point d'entrée des boutons. Une action qui n'est plus proposée
    /// (appui tardif après un changement d'état) est ignorée.
    func perform(_ action: ScreenAction) {
        guard controls.allows(action) else { return }
        switch action {
        case .stopVoice:
            stopVoice()
        case .finishDictation where isListening:
            // La reconnaissance rend le texte complet, y compris l'hypothèse en cours.
            speechInput.finishDictation()
        case .finishDictation:
            send(.finishDictation(partial: currentDictationPartial))
        case .startVoice:
            // Garder une éventuelle transcription en cours avant de relancer.
            _ = machine.handle(.stopVoice(partial: currentDictationPartial))
            send(.resumeVoice)
        default:
            send(FlowMachine.event(for: action))
        }
    }

    /// Coupe la parole et le micro, sans valider ni effacer : la dictée passe en pause
    /// avec son texte, une question reste affichée avec ses boutons.
    func stopVoice() {
        guard !state.isUsingTag else { return }
        let wasListening = isListening
        let partial = currentDictationPartial
        interruptChain()
        _ = machine.handle(.stopVoice(partial: partial))
        state = machine.state
        showRestingMessage()
        if wasListening {
            let current = generation
            effectTask = Task {
                guard current == generation, !Task.isCancelled else { return }
                await audioSession.activate()
                guard current == generation, !Task.isCancelled else { return }
                await feedback.play(.listeningEnded)
                guard current == generation, !Task.isCancelled else { return }
                audioSession.deactivate()
            }
        }
    }

    /// Tout arrêter sans rien dire (arrière-plan, appel, autre écran, Siri).
    /// Une session NFC est abandonnée ; le reste suit les règles de `stopVoice`.
    func stopAll() {
        if case .writing = state {
            lastResultMessage = Phrases.writeCanceledCheckTag
        }
        // Conserver seulement la transcription déjà reçue, jamais l'audio.
        let partial = currentDictationPartial
        interruptChain()
        if machine.state.isUsingTag { machine.reset() }
        else { _ = machine.handle(.stopVoice(partial: partial)) }
        state = machine.state
        showRestingMessage()
    }

    /// Transcription de l'écoute de dictée en cours, à conserver si elle est coupée.
    /// Pendant une confirmation, le micro écoute des réponses, pas du contenu.
    private var currentDictationPartial: String {
        guard case .askingName = state else { return "" }
        return speechInput.currentText
    }

    /// Message affiché quand la voix se tait : le dernier résultat au repos,
    /// le texte conservé pendant une pause ; une question reste affichée telle quelle.
    private func showRestingMessage() {
        switch state {
        case .idle: statusMessage = lastResultMessage ?? Phrases.welcome
        case .pausedDictation(let text, _): statusMessage = Phrases.dictationPaused(text)
        default: break
        }
        audioSession.deactivate()
    }

    // MARK: - Boucle événement → effets

    private func send(_ event: FlowEvent) {
        let wasListening = isListening
        interruptChain()
        let effects = machine.handle(event)
        state = machine.state
        guard !effects.isEmpty else {
            showRestingMessage()
            return
        }
        // Pas de trou d'affichage pendant l'activation audio : la voix est déjà engagée.
        switch effects.first {
        case .say: voiceActivity = .speaking
        case .listen: voiceActivity = .listening
        default: voiceActivity = .off
        }
        let current = generation
        effectTask = Task {
            guard current == generation, !Task.isCancelled else { return }
            await audioSession.activate()
            guard current == generation, !Task.isCancelled else { return }
            if wasListening { await feedback.play(.listeningEnded) }
            await run(effects, generation: current)
        }
    }

    /// Coupe la parole et l'écoute en cours ; la chaîne d'effets en cours s'arrêtera.
    private func interruptChain() {
        generation += 1
        effectTask?.cancel()
        effectTask = nil
        voiceActivity = .off
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
                voiceActivity = .speaking
                await announce(text, cue: cue, generation: current)

            case .recordDiagnostic(let records):
                diagnostics.add(TagDecoder.decode(records))

            case .listen(let kind):
                // Les autorisations sont obtenues avant le signal de départ.
                // Le micro ne s'ouvre qu'une fois ce son terminé.
                voiceActivity = .speaking
                let result = await speechInput.listen(kind, onReady: { [weak self] in
                    guard let self, current == self.generation, !Task.isCancelled else { return }
                    await self.feedback.play(.listening)
                    guard current == self.generation, !Task.isCancelled else { return }
                    self.voiceActivity = .listening
                })
                guard current == generation else { return }
                let didListen = isListening
                voiceActivity = .off
                if didListen { await feedback.play(.listeningEnded) }
                guard current == generation, !Task.isCancelled else { return }
                send(.heard(result))
                return

            case .readTag:
                voiceActivity = .off
                let result = await withApproachPrompt(Phrases.approachTag, generation: current) {
                    await self.tags.readTag()
                }
                guard current == generation else { return }
                send(.readFinished(result))
                return

            case .writeTag(let records, let expectedCurrent, let isSecondPass):
                voiceActivity = .off
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
        guard current == generation else { return }
        voiceActivity = .off
        // Plus rien n'attend de résultat : on rend l'audio aux autres apps.
        audioSession.deactivate()
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
        // Les annulations NFC n'ont pas de signal sonore, mais leur avertissement
        // doit aussi rester affiché si l'utilisateur coupe sa lecture vocale.
        if cue != nil || state == .idle {
            lastResultMessage = text
        }
        if let cue {
            await feedback.play(cue)
        }
        guard current == generation, !Task.isCancelled else { return }
        await speech.speak(text)
    }
}
