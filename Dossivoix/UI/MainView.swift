import SwiftUI
import DossivoixCore

/// Écran principal : solution de secours si la voix ne suffit pas.
/// Un message d'état en grand, et deux très grands boutons adaptés à l'étape du parcours :
/// « Lire » / « Écrire », « C'est bon » / « Recommencer », ou « Remplacer » / « Annuler ».
struct MainView: View {
    @Bindable var coordinator: FlowCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(coordinator.statusMessage)
                        .font(.system(.title, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .accessibilityLabel("État : \(coordinator.statusMessage)")

                    if coordinator.isListening {
                        Label("J'écoute…", systemImage: "mic.fill")
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                            // Pas d'annonce VoiceOver : le signal sonore suffit et VoiceOver
                            // ne doit pas parler pendant que le micro est ouvert.
                            .accessibilityHidden(true)
                    }

                    bigButtons

                    secondaryButtons
                }
                .padding()
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
            .sheet(item: $coordinator.textEntryRequest) { request in
                WriteSheet(prefill: request.prefill) { name in
                    coordinator.textEntryRequest = nil
                    coordinator.typedName(name)
                } onCancel: {
                    coordinator.textEntryRequest = nil
                    coordinator.cancel()
                }
            }
        }
    }

    /// Vrai pendant une session NFC : rien d'autre n'est possible.
    private var isUsingTag: Bool {
        switch coordinator.state {
        case .reading, .writing: true
        default: false
        }
    }

    // MARK: - Grands boutons

    @ViewBuilder
    private var bigButtons: some View {
        switch coordinator.state {
        case .confirmingName(let name, _, _):
            BigActionButton(
                title: "C'est bon",
                systemImage: "checkmark",
                accessibilityLabel: "C'est bon : \(name)",
                accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                foreground: HighContrast.readForeground,
                background: HighContrast.readBackground
            ) {
                coordinator.answer(.yes)
            }
            BigActionButton(
                title: "Recommencer",
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Recommencer",
                accessibilityHint: "Permet de redire le nom du dossier.",
                foreground: HighContrast.writeForeground,
                background: HighContrast.writeBackground
            ) {
                coordinator.answer(.restart)
            }

        case .confirmingReplace(let name, _, _):
            BigActionButton(
                title: "Remplacer",
                systemImage: "arrow.triangle.2.circlepath",
                accessibilityLabel: "Remplacer par \(name)",
                accessibilityHint: "Approchez ensuite à nouveau l'étiquette.",
                foreground: HighContrast.readForeground,
                background: HighContrast.readBackground
            ) {
                coordinator.answer(.yes)
            }
            BigActionButton(
                title: "Annuler",
                systemImage: "xmark",
                accessibilityLabel: "Annuler",
                accessibilityHint: "L'étiquette ne sera pas modifiée.",
                foreground: HighContrast.writeForeground,
                background: HighContrast.writeBackground
            ) {
                coordinator.answer(.cancel)
            }

        default:
            BigActionButton(
                title: "Lire",
                systemImage: "wave.3.right",
                accessibilityLabel: "Lire une étiquette",
                accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                foreground: HighContrast.readForeground,
                background: HighContrast.readBackground
            ) {
                coordinator.startReading()
            }
            .disabled(isUsingTag)

            BigActionButton(
                title: "Écrire",
                systemImage: "square.and.pencil",
                accessibilityLabel: "Écrire une étiquette",
                accessibilityHint: "L'app vous demandera de dire le nom du dossier.",
                foreground: HighContrast.writeForeground,
                background: HighContrast.writeBackground
            ) {
                coordinator.startWriting()
            }
            .disabled(isUsingTag)
        }
    }

    // MARK: - Boutons secondaires

    private var secondaryButtons: some View {
        VStack(spacing: 16) {
            Button {
                coordinator.openKeyboardEntry(prefill: currentName)
            } label: {
                Label("Saisir le nom au clavier", systemImage: "keyboard")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .disabled(isUsingTag)

            if coordinator.state != .idle && !isUsingTag {
                Button {
                    coordinator.cancel()
                } label: {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityHint("Arrête le parcours en cours.")
            }
        }
    }

    /// Nom en cours de confirmation, pour pré-remplir la saisie au clavier.
    private var currentName: String? {
        switch coordinator.state {
        case .confirmingName(let name, _, _), .confirmingReplace(let name, _, _), .offeringRetry(let name, _):
            name
        default:
            nil
        }
    }
}

/// Saisie du nom au clavier, en secours de la dictée.
private struct WriteSheet: View {
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isFieldFocused: Bool

    init(prefill: String?, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _name = State(initialValue: prefill ?? "")
    }

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
                    Button("Annuler", action: onCancel)
                }
            }
            .onAppear { isFieldFocused = true }
            .interactiveDismissDisabled()
        }
    }

    private func confirm() {
        guard !preparedName.isEmpty else { return }
        onConfirm(preparedName)
    }
}

#Preview("Lecture simulée") {
    MainView(coordinator: FlowCoordinator(
        tags: FakeTagService(readResult: .success(
            SmartVisionFormat.standard.records(forFolderName: "Dossier panneau solaire")
        )),
        speech: SilentSpeechOutput(),
        speechInput: ScriptedSpeechInput(answers: []),
        feedback: SilentFeedback(),
        audioSession: SilentAudioSession()
    ))
}
