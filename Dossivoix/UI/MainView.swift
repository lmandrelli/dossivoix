import SwiftUI
import DossivoixCore

/// Écran principal : solution de secours si la voix ne suffit pas.
///
/// Disposition figée : rien ne bouge ni ne change de taille d'un état à l'autre.
/// - en haut, le message en grand, dans une zone de hauteur fixe ;
/// - au milieu, deux très grands boutons toujours à la même place : seul leur texte change
///   (« Lire » / « Écrire », « C'est bon » / « Recommencer », « Remplacer » / « Annuler ») ;
/// - en bas, « Clavier » et « Arrêter », toujours présents (grisés quand inutiles) ;
/// - tout en bas, une zone réservée au panneau « J'écoute ».
/// Deux couleurs seulement (voir Palette) : noir sur blanc en thème clair, ce qui donne
/// du blanc sur noir avec l'inversion intelligente, et blanc sur noir en thème foncé.
struct MainView: View {
    @Bindable var coordinator: FlowCoordinator
    @Environment(\.palette) private var palette

    /// Hauteur réservée au panneau « J'écoute » (toujours réservée, même vide).
    private static let listeningSlotHeight: CGFloat = 112

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    Text(coordinator.statusMessage)
                        .font(.system(.title, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(height: geometry.size.height * 0.24)
                        .accessibilityLabel("État : \(coordinator.statusMessage)")

                    actionButton(primaryAction)
                    actionButton(secondaryAction)

                    secondaryButtons
                        .frame(height: 60)

                    Color.clear
                        .frame(height: Self.listeningSlotHeight)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                ListeningPanel(isVisible: coordinator.isListening)
                    .frame(height: Self.listeningSlotHeight)
            }
            .background(palette.paper)
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
        // Aucune animation implicite : les changements d'état sont instantanés.
        .transaction { $0.animation = nil }
    }

    // MARK: - Contenu des grands boutons selon l'étape

    /// Ce qu'affiche et fait un grand bouton.
    private struct ButtonContent {
        let title: String
        let systemImage: String
        let accessibilityLabel: String
        let accessibilityHint: String
        let isEnabled: Bool
        let action: () -> Void
    }

    /// Vrai pendant une session NFC : rien d'autre n'est possible.
    private var isUsingTag: Bool {
        switch coordinator.state {
        case .reading, .writing: true
        default: false
        }
    }

    private var primaryAction: ButtonContent {
        switch coordinator.state {
        case .confirmingName(let name, _, _):
            ButtonContent(title: "C'est bon", systemImage: "checkmark",
                          accessibilityLabel: "C'est bon : \(name)",
                          accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                          isEnabled: true) { coordinator.answer(.yes) }
        case .confirmingReplace(let name, _, _):
            ButtonContent(title: "Remplacer", systemImage: "arrow.triangle.2.circlepath",
                          accessibilityLabel: "Remplacer par \(name)",
                          accessibilityHint: "Approchez ensuite à nouveau l'étiquette.",
                          isEnabled: true) { coordinator.answer(.yes) }
        default:
            ButtonContent(title: "Lire", systemImage: "wave.3.right",
                          accessibilityLabel: "Lire une étiquette",
                          accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                          isEnabled: !isUsingTag) { coordinator.startReading() }
        }
    }

    private var secondaryAction: ButtonContent {
        switch coordinator.state {
        case .confirmingName:
            ButtonContent(title: "Recommencer", systemImage: "arrow.counterclockwise",
                          accessibilityLabel: "Recommencer",
                          accessibilityHint: "Permet de redire le nom du dossier.",
                          isEnabled: true) { coordinator.answer(.restart) }
        case .confirmingReplace:
            ButtonContent(title: "Annuler", systemImage: "xmark",
                          accessibilityLabel: "Annuler",
                          accessibilityHint: "L'étiquette ne sera pas modifiée.",
                          isEnabled: true) { coordinator.answer(.cancel) }
        default:
            ButtonContent(title: "Écrire", systemImage: "square.and.pencil",
                          accessibilityLabel: "Écrire une étiquette",
                          accessibilityHint: "L'app vous demandera de dire le nom du dossier.",
                          isEnabled: !isUsingTag) { coordinator.startWriting() }
        }
    }

    private func actionButton(_ content: ButtonContent) -> some View {
        BigActionButton(
            title: content.title,
            systemImage: content.systemImage,
            accessibilityLabel: content.accessibilityLabel,
            accessibilityHint: content.accessibilityHint,
            action: content.action
        )
        .disabled(!content.isEnabled)
    }

    // MARK: - Boutons secondaires (toujours présents)

    private var secondaryButtons: some View {
        HStack(spacing: 16) {
            smallButton("Clavier", systemImage: "keyboard",
                        accessibilityLabel: "Saisir le nom au clavier",
                        isEnabled: !isUsingTag) {
                coordinator.openKeyboardEntry(prefill: currentName)
            }
            smallButton("Arrêter", systemImage: "stop.fill",
                        accessibilityLabel: "Arrêter",
                        isEnabled: coordinator.state != .idle && !isUsingTag) {
                coordinator.cancel()
            }
        }
    }

    private func smallButton(
        _ title: String, systemImage: String, accessibilityLabel: String,
        isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.paper, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.ink, lineWidth: 3))
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(StillButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
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
    @Environment(\.palette) private var palette

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
                    .foregroundStyle(palette.ink)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.ink, lineWidth: 3))
                    .submitLabel(.done)
                    .focused($isFieldFocused)
                    .onSubmit(confirm)

                BigActionButton(
                    title: "Écrire sur l'étiquette",
                    systemImage: "wave.3.right",
                    accessibilityLabel: "Écrire sur l'étiquette",
                    accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.",
                    action: confirm
                )
                .frame(height: 150)
                .disabled(preparedName.isEmpty)

                Spacer()
            }
            .padding()
            .background(palette.paper)
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
    .adaptivePalette()
}
