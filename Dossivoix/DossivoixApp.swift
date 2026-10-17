import SwiftUI

/// Point d'entrée de l'app.
@main
struct DossivoixApp: App {
    @State private var coordinator = FlowCoordinator.live()
    @State private var launchRouter = LaunchRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Délai avant de démarrer un parcours demandé par Siri : laisse Siri finir de parler
    /// et l'écran de l'app s'afficher, pour ne pas couvrir les deux voix.
    private static let siriHandOffDelay = Duration.milliseconds(800)

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator)
                .onChange(of: launchRouter.pending) {
                    startPendingAction()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                startPendingAction()
            case .background:
                // L'app ne parle ni n'écoute quand elle n'est plus à l'écran.
                coordinator.stopAll()
            default:
                break
            }
        }
    }

    /// Démarre le parcours demandé par un App Intent, dès que l'app est au premier plan
    /// (le NFC n'est possible qu'à ce moment-là). Aucune action à l'écran n'est nécessaire.
    private func startPendingAction() {
        guard scenePhase == .active, let action = launchRouter.take() else { return }
        Task {
            try? await Task.sleep(for: Self.siriHandOffDelay)
            switch action {
            case .read: coordinator.startReading()
            case .write: coordinator.startWriting()
            }
        }
    }
}
