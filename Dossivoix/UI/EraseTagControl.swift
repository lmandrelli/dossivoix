import SwiftUI
import DossivoixCore

/// Contrôle avancé intégré directement sous le lien Diagnostic dans À propos.
struct EraseTagControl: View {
    let log: DiagnosticLog
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = CoreNFCTagService()
    @State private var feedback = SoundAndHapticFeedback()
    @State private var audioSession = AudioSessionManager()
    @State private var confirming = false
    @State private var isBusy = false
    @State private var status: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vider une étiquette supprime son contenu NDEF pour la réutiliser. Son identité et ses paramètres sont conservés ; cela ne réinitialise pas ses paramètres d’usine.")
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                confirming = true
            } label: {
                Label("Vider une étiquette", systemImage: "eraser")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.ink, lineWidth: 3))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isBusy)
            .accessibilityHint("Demande confirmation avant d’ouvrir le lecteur NFC.")
            if let status {
                Text(status)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(palette.ink)
        .buttonStyle(StillButtonStyle())
        .alert("Effacer le contenu de l’étiquette ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Effacer", role: .destructive) { erase() }
        } message: {
            Text("Le contenu de la prochaine étiquette approchée sera supprimé. Cet effacement ne peut pas être annulé.")
        }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stop() }
        }
    }

    private func erase() {
        guard !isBusy else { return }
        isBusy = true
        status = "Approchez l’étiquette à vider et gardez-la immobile."
        task = Task { @MainActor in
            let result = await service.eraseTag()
            guard !Task.isCancelled else { return }
            defer {
                if !Task.isCancelled {
                    isBusy = false
                    audioSession.deactivate()
                }
            }
            switch result {
            case .success:
                status = "Étiquette vidée. Elle est prête à être réutilisée."
                log.add(TagDecoder.decode([]))
                await audioSession.activate()
                guard !Task.isCancelled else { return }
                await feedback.play(.success)
            case .failure(let error):
                status = error == .userCanceled ? "Effacement annulé." : Phrases.message(for: error, during: .writing)
                log.addFailure(error, during: .writing, details: "Effacement avancé\n" + service.lastDiagnosticReport)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        service.cancel()
        feedback.stop()
        audioSession.deactivate()
        if isBusy { status = "Effacement annulé." }
        isBusy = false
    }
}
