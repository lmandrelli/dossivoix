import SwiftUI
import DossivoixCore

enum MainDestination: Hashable {
    case about
    case diagnostic
}

/// Écran principal : solution de secours si la voix ne suffit pas.
///
/// Disposition adaptée à la largeur ; aux tailles d'accessibilité ou hauteurs
/// compactes, le contenu peut défiler pour garder messages et actions lisibles.
/// - en haut, le message en grand, dans une zone de hauteur fixe ;
/// - au milieu, deux très grands boutons toujours à la même place : seul leur texte change
///   (« Lire » / « Écrire », « C'est bon » / « Recommencer », « Remplacer » / « Annuler ») ;
/// - en bas, « Clavier » et « Arrêter », toujours présents (grisés quand inutiles) ;
/// - tout en bas, une zone réservée au panneau « J'écoute ».
/// Deux couleurs seulement (voir Palette) : noir sur blanc en thème clair, ce qui donne
/// du blanc sur noir avec l'inversion intelligente, et blanc sur noir en thème foncé.
struct MainView: View {
    @Bindable var coordinator: FlowCoordinator
    @Binding var navigationPath: [MainDestination]
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Hauteur réservée au panneau « J'écoute » (toujours réservée, même vide).
    private static let listeningSlotHeight: CGFloat = 112
    /// 24 % pour l'état, 2 × 120 pour les grandes actions, 60 pour les petites,
    /// 112 pour l'écoute, 4 espacements de 16 et 8 de marge haute : environ 637 pt.
    private static let minimumFixedHeight: CGFloat = 640
    private static let openPortraitMinimumHeight: CGFloat = 720
    private static let wideMinimumHeight: CGFloat = 450

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                if let division = activeDivision(in: geometry) {
                    foldedContent(size: geometry.size, division: division)
                } else {
                    Group {
                        if !dynamicTypeSize.isAccessibilitySize && geometry.size.width >= 780 {
                            wideContent(height: geometry.size.height)
                        } else if !dynamicTypeSize.isAccessibilitySize && geometry.size.width >= 550 {
                            openPortraitContent(height: geometry.size.height)
                        } else if dynamicTypeSize.isAccessibilitySize || geometry.size.height < Self.minimumFixedHeight {
                            scrollingContent(minimumActionHeight: 120, maximumWidth: nil)
                        } else {
                            compactContent(height: geometry.size.height)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .overlay(alignment: .bottom) {
                        ListeningPanel(isVisible: coordinator.isListening)
                            .frame(height: Self.listeningSlotHeight)
                            .allowsHitTesting(false)
                    }
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
                    case .about: AboutView()
                    case .diagnostic: DiagnosticView(log: coordinator.diagnostics)
                    }
                }
                .onAppear { coordinator.stopAll() }
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

    private var statusText: some View {
        Text(coordinator.statusMessage)
            .font(.system(.title, weight: .bold))
            .foregroundStyle(palette.ink)
            .multilineTextAlignment(.center)
            .accessibilityLabel("État : \(coordinator.statusMessage)")
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
        ScrollView {
            VStack(spacing: 16) {
                statusText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                actionButton(primaryAction)
                    .frame(minHeight: 120)
                actionButton(secondaryAction)
                    .frame(minHeight: 120)
                secondaryButtons
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, Self.listeningSlotHeight)
        .overlay(alignment: .bottom) {
            ListeningPanel(isVisible: coordinator.isListening)
                .frame(height: Self.listeningSlotHeight)
                .allowsHitTesting(false)
        }
        .frame(width: region.width, height: region.height)
        .clipped()
        .position(x: region.midX, y: region.midY)
    }

    private func foldedInformation(in region: CGRect) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                statusText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .frame(minHeight: max(0, region.height - Self.listeningSlotHeight))
            }
            ListeningPanel(isVisible: coordinator.isListening)
                .frame(height: Self.listeningSlotHeight)
                .allowsHitTesting(false)
        }
        .frame(width: region.width, height: region.height)
        .clipped()
        .position(x: region.midX, y: region.midY)
    }

    private func foldedControls(in region: CGRect) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                actionButton(primaryAction)
                    .frame(minHeight: 120)
                actionButton(secondaryAction)
                    .frame(minHeight: 120)
                secondaryButtons
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, minHeight: region.height)
        }
        .frame(width: region.width, height: region.height)
        .clipped()
        .position(x: region.midX, y: region.midY)
    }

    private func scrollingContent(minimumActionHeight: CGFloat, maximumWidth: CGFloat?) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                statusText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                actionButton(primaryAction)
                    .frame(minHeight: minimumActionHeight)
                actionButton(secondaryAction)
                    .frame(minHeight: minimumActionHeight)
                secondaryButtons
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
        }
        // Réserver le viewport : aucune action ne passe sous le panneau.
        .padding(.bottom, Self.listeningSlotHeight)
    }

    private func compactContent(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            statusText
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: height * 0.24)

            actionButton(primaryAction)
                .frame(minHeight: 120)
            actionButton(secondaryAction)
                .frame(minHeight: 120)

            secondaryButtons
                .frame(height: 60)

            Color.clear
                .frame(height: Self.listeningSlotHeight)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func openPortraitContent(height: CGFloat) -> some View {
        if height < Self.openPortraitMinimumHeight {
            scrollingContent(minimumActionHeight: 160, maximumWidth: 640)
        } else {
            VStack(spacing: 16) {
                statusText
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: height * 0.2)

                actionButton(primaryAction)
                    .frame(minHeight: 160, maxHeight: .infinity)
                actionButton(secondaryAction)
                    .frame(minHeight: 160, maxHeight: .infinity)

                secondaryButtons
                    .frame(height: 60)

                Color.clear
                    .frame(height: Self.listeningSlotHeight)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func wideContent(height: CGFloat) -> some View {
        if height < Self.wideMinimumHeight {
            ScrollView {
                VStack(spacing: 16) {
                    statusText
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 16) {
                        actionButton(primaryAction)
                        actionButton(secondaryAction)
                    }
                    .frame(minHeight: 120)
                    secondaryButtons
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, Self.listeningSlotHeight)
        } else {
            VStack(spacing: 16) {
                statusText
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: min(100, height * 0.2))

                HStack(spacing: 16) {
                    actionButton(primaryAction)
                    actionButton(secondaryAction)
                }
                .frame(minHeight: 120, maxHeight: .infinity)

                secondaryButtons
                    .frame(height: 60)

                Color.clear
                    .frame(height: Self.listeningSlotHeight)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.5)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity,
                       minHeight: 60,
                       maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
                .padding(dynamicTypeSize.isAccessibilitySize ? 16 : 0)
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
            ScrollView {
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
                    .frame(minHeight: 150)
                    .disabled(preparedName.isEmpty)
                }
                .padding()
            }
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
    ), navigationPath: .constant([]))
    .adaptivePalette()
}
