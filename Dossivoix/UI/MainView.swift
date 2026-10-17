import SwiftUI
import DossivoixCore

/// Écran principal : solution de secours si la voix ne suffit pas.
/// Un message d'état en grand, et deux très grands boutons « Lire » et « Écrire ».
struct MainView: View {
    let coordinator: FlowCoordinator

    @State private var isShowingWriteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(coordinator.statusMessage)
                        .font(.system(.title, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .accessibilityLabel("État : \(coordinator.statusMessage)")

                    BigActionButton(
                        title: "Lire",
                        systemImage: "wave.3.right",
                        accessibilityLabel: "Lire une étiquette",
                        accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                        foreground: HighContrast.readForeground,
                        background: HighContrast.readBackground
                    ) {
                        Task { await coordinator.startReading() }
                    }

                    BigActionButton(
                        title: "Écrire",
                        systemImage: "square.and.pencil",
                        accessibilityLabel: "Écrire une étiquette",
                        accessibilityHint: "Permet de saisir le nom du dossier.",
                        foreground: HighContrast.writeForeground,
                        background: HighContrast.writeBackground
                    ) {
                        isShowingWriteSheet = true
                    }
                }
                .padding()
                .disabled(coordinator.isBusy)
            }
            .navigationTitle(AppIdentity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Accès discret à l'écran Diagnostic.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Diagnostic") {
                        DiagnosticView(log: coordinator.diagnostics)
                    }
                    .font(.footnote)
                    .accessibilityHint("Détail technique des dernières étiquettes lues, à partager.")
                }
            }
            .sheet(isPresented: $isShowingWriteSheet) {
                WriteSheet { name in
                    isShowingWriteSheet = false
                    Task { await coordinator.startWriting(folderName: name) }
                }
            }
        }
    }
}

/// Saisie du nom au clavier, en secours de la dictée.
private struct WriteSheet: View {
    let onConfirm: (String) -> Void

    @State private var name = ""
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var preparedName: String { FolderName.preparedForWriting(name) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Nom du dossier", text: $name)
                    .font(.title)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .focused($isFieldFocused)
                    .onSubmit(confirm)

                BigActionButton(
                    title: "Écrire sur l'étiquette",
                    systemImage: "wave.3.right",
                    accessibilityLabel: "Écrire sur l'étiquette",
                    accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                    foreground: HighContrast.writeForeground,
                    background: HighContrast.writeBackground,
                    action: confirm
                )
                .disabled(preparedName.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Écrire une étiquette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }

    private func confirm() {
        guard !preparedName.isEmpty else { return }
        onConfirm(preparedName)
    }
}

#Preview("Lecture simulée") {
    MainView(coordinator: FlowCoordinator(
        tagReader: FakeTagReader(result: .success(
            SmartVisionFormat.standard.records(forFolderName: "Dossier panneau solaire")
        )),
        speech: SilentSpeechOutput(),
        feedback: SilentFeedback(),
        audioSession: SilentAudioSession()
    ))
}
