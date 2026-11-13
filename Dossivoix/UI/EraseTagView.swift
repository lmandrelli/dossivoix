import SwiftUI
import DossivoixCore

/// Outil volontairement séparé des parcours principaux de lecture et d'écriture.
struct EraseTagView: View {
    let log: DiagnosticLog
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = CoreNFCTagService()
    @State private var speech = AdaptiveSpeechOutput.live()
    @State private var confirming = false
    @State private var isBusy = false
    @State private var status = "L’étiquette vidée pourra être réutilisée pour un nouveau texte."
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Fonction avancée")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Supprime le contenu NDEF de l’étiquette. Son identité et ses paramètres sont conservés ; elle reste réinscriptible si elle n’est pas verrouillée.")
                Text("Cet effacement concerne le contenu lisible par les applications NFC. Il ne réinitialise pas les paramètres d’usine.")
                Text(status)
                    .font(.title3.bold())
                    .accessibilityLabel("État : " + status)
                Button {
                    speech.stop()
                    confirming = true
                } label: {
                    Label("Vider une étiquette", systemImage: "eraser")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.ink, lineWidth: 3))
                }
                .disabled(isBusy)
                .accessibilityHint("Demande confirmation avant d’ouvrir le lecteur NFC.")
                if isBusy {
                    Button("Annuler l’effacement") { stop() }
                        .font(.headline)
                        .frame(minHeight: 48)
                }
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(palette.paper)
        .buttonStyle(StillButtonStyle())
        .navigationTitle("Vider une étiquette")
        .navigationBarTitleDisplayMode(.inline)
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
            isBusy = false
            switch result {
            case .success:
                status = "Étiquette vidée. Elle est prête à être réutilisée."
                log.add(TagDecoder.decode([]))
            case .failure(let error):
                status = error == .userCanceled ? "Effacement annulé." : Phrases.message(for: error, during: .writing)
                log.addFailure(error, during: .writing, details: "Effacement avancé\n" + service.lastDiagnosticReport)
            }
            await speech.speak(status)
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        service.cancel()
        speech.stop()
        if isBusy { status = "Effacement annulé." }
        isBusy = false
    }
}
