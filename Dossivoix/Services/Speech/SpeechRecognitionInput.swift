import AVFoundation
import Speech
import DossivoixCore

/// Une session système, séparée des délais et autorisations pour tester les interruptions.
@MainActor
protocol SpeechRecognitionSession: AnyObject {
    var isAvailable: Bool { get }
    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool, SpeechUtterance?) -> Void) throws
    func stop()
}

/// Écoutes bornées en français. Chaque écoute possède une génération : ni les autorisations,
/// ni les callbacks, ni les timers d'une ancienne écoute ne peuvent agir sur la suivante.
@MainActor
final class SpeechRecognitionInput: SpeechInput {
    private let session: SpeechRecognitionSession
    private let authorizeSpeech: @MainActor () async -> Bool
    private let authorizeMicrophone: @MainActor () async -> Bool
    private var generation = 0
    private var continuation: CheckedContinuation<ListenResult, Never>?
    private var latestText = ""
    private var transcript = DictationTranscript()
    private var kind: ListenKind = .answer
    private let timingOverride: ListenTiming?
    var currentText: String { DictationCommand.content(latestText) }

    func finishDictation() {
        guard kind == .name, continuation != nil else { return }
        finish(.dictated(currentText))
    }

    private var silenceTimeout: Double = 1
    private var silenceTimer: Task<Void, Never>?
    private var deadlineTimer: Task<Void, Never>?

    init(
        session: SpeechRecognitionSession? = nil,
        timingOverride: ListenTiming? = nil,
        authorizeSpeech: @escaping @MainActor () async -> Bool = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        },
        authorizeMicrophone: @escaping @MainActor () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.session = session ?? AppleSpeechRecognitionSession()
        self.timingOverride = timingOverride
        self.authorizeSpeech = authorizeSpeech
        self.authorizeMicrophone = authorizeMicrophone
    }

    func listen(_ kind: ListenKind, onReady: @escaping @MainActor () async -> Void) async -> ListenResult {
        cancel()
        let current = generation
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .silence }
            let speechAllowed = await authorizeSpeech()
            guard current == generation, !Task.isCancelled else { return .silence }
            guard speechAllowed else { return .unavailable }
            let microphoneAllowed = await authorizeMicrophone()
            guard current == generation, !Task.isCancelled else { return .silence }
            guard microphoneAllowed, session.isAvailable else { return .unavailable }

            await onReady()
            guard current == generation, !Task.isCancelled else { return .silence }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                latestText = ""
                transcript = DictationTranscript()
                self.kind = kind
                let timing = timingOverride ?? kind.timing
                silenceTimeout = timing.silenceTimeout
                do {
                    try session.start(kind) { [weak self] text, isFinal, failed, utterance in
                        self?.received(text: text, isFinal: isFinal, failed: failed, utterance: utterance, generation: current)
                    }
                    guard current == generation else { return }
                    silenceTimer = timer(after: timing.initialTimeout, generation: current)
                    deadlineTimer = timer(after: timing.maxDuration, generation: current)
                } catch {
                    guard current == generation else { return }
                    Log.speech.error("Écoute impossible : \(error.localizedDescription)")
                    finish(.unavailable)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.cancel()
            }
        }
    }

    func cancel() { finish(.silence) }

    private func received(text: String?, isFinal: Bool, failed: Bool, utterance: SpeechUtterance?, generation current: Int) {
        guard current == generation, continuation != nil else { return }
        let combined: String?
        if kind == .name, let text, !text.isEmpty {
            combined = transcript.receive(text, utterance: utterance)
        } else { combined = text }
        if let text = combined, !text.isEmpty, text != latestText {
            latestText = text
            silenceTimer?.cancel()
            silenceTimer = timer(after: silenceTimeout, generation: current)
            if kind == .name, DictationCommand.action(in: text) != nil {
                silenceTimer?.cancel()
                // Une hypothèse partielle peut être corrigée : attendre sa stabilité.
                silenceTimer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                    guard let self, current == self.generation else { return }
                    self.finishCommand()
                }
            }
        }
        if isFinal || failed {
            if kind == .name {
                // Une erreur ne valide jamais une commande issue d'une hypothèse partielle.
                if !failed, finishCommand() { return }
                finish(.paused(currentText))
            } else { finishWithLatestText() }
        }
    }

    private func timer(after seconds: Double, generation current: Int) -> Task<Void, Never> {
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, current == self.generation, !Task.isCancelled else { return }
            self.finishWithLatestText()
        }
    }

    @discardableResult
    private func finishCommand() -> Bool {
        switch DictationCommand.action(in: latestText) {
        case .finish(let text): finish(.dictated(text))
        case .cancel(let text): finish(.stopped(text))
        case nil: return false
        }
        return true
    }

    private func finishWithLatestText() {
        if kind == .name { finish(.paused(currentText)) }
        else { finish(latestText.isEmpty ? .silence : .text(latestText)) }
    }

    private func finish(_ result: ListenResult) {
        // Invalider les callbacks avant de demander l'annulation au framework.
        generation += 1
        let waiting = continuation
        continuation = nil
        silenceTimer?.cancel()
        deadlineTimer?.cancel()
        silenceTimer = nil
        deadlineTimer = nil
        session.stop()
        latestText = ""
        transcript = DictationTranscript()
        waiting?.resume(returning: result)
    }
}

/// Accès aux frameworks Apple. L'audio n'est pas enregistré par Dossivoix ; le service
/// peut traiter l'audio chez Apple si la reconnaissance sur l'appareil n'est pas disponible.
@MainActor
private final class AppleSpeechRecognitionSession: SpeechRecognitionSession {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private struct Unavailable: Error {}

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool, SpeechUtterance?) -> Void) throws {
        guard let recognizer else { throw Unavailable() }
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        switch kind {
        case .name:
            request.taskHint = .dictation
            request.contextualStrings = ["terminer la dictée", "annuler la dictée", "texte littéral"]
        case .answer:
            request.taskHint = .confirmation
            request.contextualStrings = ["oui", "non", "recommencer", "annuler", "encore", "écrire", "remplacer"]
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Unavailable() }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasInputTap = true
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            let metadata = result?.speechRecognitionMetadata
            let utterance: SpeechUtterance?
            if let metadata, metadata.speechDuration > 0 {
                utterance = SpeechUtterance(start: metadata.speechStartTimestamp,
                    end: metadata.speechStartTimestamp + metadata.speechDuration, isComplete: true)
            } else if let segments = result?.bestTranscription.segments,
                      let first = segments.first, let last = segments.last, last.duration > 0 {
                utterance = SpeechUtterance(start: first.timestamp,
                    end: last.timestamp + last.duration, isComplete: false)
            } else { utterance = nil }
            Task { @MainActor in receive(text, isFinal, failed, utterance) }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        // Ne pas initialiser l'entrée audio avant que l'utilisateur autorise le micro.
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
