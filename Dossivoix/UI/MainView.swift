import SwiftUI
import DossivoixCore

enum MainDestination: Hashable {
    case about
    case diagnostic
}

/// Écran principal : solution de secours si la voix ne suffit pas.
///
/// Trois emplacements fixes en bas : deux grands boutons de parcours, puis la voix
/// (voir `ScreenControls` pour la matrice état → actions). Le message occupe le reste
/// et sa taille s'ajuste ; rien ne se déplace d'un état à l'autre.
/// Deux couleurs seulement (voir Palette) : noir sur blanc en thème clair, ce qui donne
/// du blanc sur noir avec l'inversion intelligente, et blanc sur noir en thème foncé.
struct MainView: View {
    @Bindable var coordinator: FlowCoordinator
    @Binding var navigationPath: [MainDestination]
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                if let division = activeDivision(in: geometry) {
                    foldedContent(size: geometry.size, division: division)
                } else {
                    anchoredContent(size: geometry.size)
                }
            }
            .background(palette.paper)
            .navigationTitle(AppIdentity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: MainDestination.about) {
                        Label("À propos", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("À propos")
                    .accessibilityHint("Confidentialité, assistance et contact du développeur.")
                }
            }
            .navigationDestination(for: MainDestination.self) { destination in
                Group {
                    switch destination {
                    case .about: AboutView(log: coordinator.diagnostics)
                    case .diagnostic: DiagnosticView(log: coordinator.diagnostics)
                    }
                }
                .onAppear { coordinator.stopAll() }
            }
        }
        // Aucune animation implicite : les changements d'état sont instantanés.
        .transaction { $0.animation = nil }
    }

    /// La taille diminue pour garder le message dans l'espace disponible.
    private var statusText: some View {
        Text(coordinator.statusMessage)
            .font(.system(.largeTitle, weight: .bold))
            .foregroundStyle(palette.ink)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("État : \(coordinator.statusMessage)")
    }

    private func anchoredContent(size: CGSize, showMessage: Bool = true) -> some View {
        let horizontal = size.width > size.height && size.width > 500
        let actionHeight = min(170.0, max(64.0, size.height * (horizontal ? 0.32 : 0.22)))
        return VStack(spacing: 12) {
            if showMessage { statusText.layoutPriority(1) }
            else { Spacer(minLength: 0) }
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
            layout {
                actionButton(primaryAction).frame(height: actionHeight)
                actionButton(secondaryAction).frame(height: actionHeight)
            }
            VoiceButton(slot: controls.voice, activity: coordinator.voiceActivity) {
                perform(controls.voice.action)
            }
            .frame(height: 80)
        }
        .padding(16)
        .frame(width: size.width, height: size.height)
    }

    private struct FoldDivision {
        let frame: CGRect
        let isHorizontal: Bool
    }

    /// La frame inclut déjà les marges de sécurité de la charnière. Les coordonnées
    /// restent physiques car les groupes sont placés avec `position(x:y:)`.
    private func activeDivision(in geometry: GeometryProxy) -> FoldDivision? {
        guard #available(iOS 27.1, *) else { return nil }
        let bounds = CGRect(origin: .zero, size: geometry.size)
        for region in geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed) {
            let frame = region.frame.intersection(bounds)
            if !frame.isNull && !frame.isEmpty {
                return FoldDivision(frame: frame,
                                    isHorizontal: region.frame.width >= region.frame.height)
            }
        }
        return nil
    }

    @ViewBuilder
    private func foldedContent(size: CGSize, division: FoldDivision) -> some View {
        let frame = division.frame
        if division.isHorizontal {
            // Pose « ordinateur » : lecture en haut, commandes accessibles en bas.
            let upper = CGRect(x: 0, y: 0, width: size.width, height: frame.minY)
            let lower = CGRect(x: 0, y: frame.maxY,
                               width: size.width, height: size.height - frame.maxY)
            if upper.height > 0 && lower.height > 0 {
                foldedInformation(in: upper)
                foldedControls(in: lower)
            } else {
                foldedSingleRegion(in: upper.height > 0 ? upper : lower)
            }
        } else {
            // Pose « livre » : lecture à gauche, commandes sur la page droite.
            let left = CGRect(x: 0, y: 0, width: frame.minX, height: size.height)
            let right = CGRect(x: frame.maxX, y: 0,
                               width: size.width - frame.maxX, height: size.height)
            if left.width > 0 && right.width > 0 {
                foldedInformation(in: left)
                foldedControls(in: right)
            } else {
                foldedSingleRegion(in: left.width > 0 ? left : right)
            }
        }
    }

    private func foldedSingleRegion(in region: CGRect) -> some View {
        anchoredContent(size: region.size)
            .clipped()
            .position(x: region.midX, y: region.midY)
    }

    private func foldedInformation(in region: CGRect) -> some View {
        statusText.padding(16)
            .frame(width: region.width, height: region.height)
            .clipped()
            .position(x: region.midX, y: region.midY)
    }

    private func foldedControls(in region: CGRect) -> some View {
        anchoredContent(size: region.size, showMessage: false)
            .clipped()
            .position(x: region.midX, y: region.midY)
    }

    // MARK: - Contenu des grands boutons selon l'étape

    private var controls: ScreenControls { coordinator.controls }
    private var primaryAction: ControlSlot { controls.primary }
    private var secondaryAction: ControlSlot { controls.secondary }

    private func perform(_ action: ScreenAction) {
        coordinator.perform(action)
        // Avec VoiceOver, l'arrêt touché n'est pas prononcé par l'app : VoiceOver le confirme.
        if action == .stopVoice {
            AccessibilityNotification.Announcement("Voix arrêtée").post()
        }
    }

    /// Ce qu'affiche un grand bouton : un seul sens par action, quel que soit l'état.
    private struct ButtonContent {
        let title: String
        let systemImage: String
        let accessibilityLabel: String
        let accessibilityHint: String
    }

    private func content(for action: ScreenAction) -> ButtonContent {
        switch action {
        case .read:
            ButtonContent(title: "Lire", systemImage: "wave.3.right",
                          accessibilityLabel: "Lire une étiquette",
                          accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.")
        case .write:
            ButtonContent(title: "Écrire", systemImage: "square.and.pencil",
                          accessibilityLabel: "Écrire une étiquette",
                          accessibilityHint: "L'app vous demandera de dire le nom du dossier.")
        case .finishDictation:
            ButtonContent(title: "Terminer", systemImage: "checkmark",
                          accessibilityLabel: "Terminer la dictée",
                          accessibilityHint: "Le texte sera relu avant confirmation. Rien n'est encore écrit.")
        case .abandonWriting:
            ButtonContent(title: "Abandonner", systemImage: "trash",
                          accessibilityLabel: "Abandonner l'écriture",
                          accessibilityHint: "Le texte dicté est effacé. Aucune étiquette n'est écrite.")
        case .confirmName:
            ButtonContent(title: "C'est bon", systemImage: "checkmark",
                          accessibilityLabel: "C'est bon : \(pendingName)",
                          accessibilityHint: "Approchez ensuite le haut de l'iPhone de l'étiquette.")
        case .restartDictation:
            ButtonContent(title: "Recommencer", systemImage: "arrow.counterclockwise",
                          accessibilityLabel: "Recommencer la dictée",
                          accessibilityHint: "Le nom relu est effacé et vous pouvez le redire.")
        case .replace:
            ButtonContent(title: "Remplacer", systemImage: "arrow.triangle.2.circlepath",
                          accessibilityLabel: "Remplacer par \(pendingName)",
                          accessibilityHint: "Approchez ensuite à nouveau l'étiquette.")
        case .keepTag:
            ButtonContent(title: "Garder", systemImage: "hand.raised",
                          accessibilityLabel: "Garder l'étiquette",
                          accessibilityHint: "L'étiquette ne sera pas modifiée.")
        case .startVoice, .stopVoice:
            // Toujours dans le troisième emplacement (VoiceButton).
            ButtonContent(title: "Voix", systemImage: "mic.fill", accessibilityLabel: "Voix", accessibilityHint: "")
        }
    }

    private var pendingName: String {
        switch coordinator.state {
        case .confirmingName(let name, _, _), .confirmingReplace(let name, _, _): name
        default: ""
        }
    }

    private func actionButton(_ slot: ControlSlot) -> some View {
        let content = content(for: slot.action)
        return BigActionButton(
            title: content.title,
            systemImage: content.systemImage,
            accessibilityLabel: content.accessibilityLabel,
            accessibilityHint: content.accessibilityHint,
            fitsAvailableSpace: true
        ) { perform(slot.action) }
        .disabled(!slot.isEnabled)
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
    ), navigationPath: .constant([]))
    .adaptivePalette()
}
