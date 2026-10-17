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
                // Noir sur blanc en thème clair (blanc sur noir avec l'inversion intelligente),
                // blanc sur noir en thème foncé. Voir Palette.
                .adaptivePalette()
                .task(id: scenePhase == .active ? launchRouter.pending : nil) {
                    // SwiftUI annule cette tâche si l'app quitte le premier plan
                    // ou si une autre action remplace la demande de Siri.
                    guard scenePhase == .active, launchRouter.pending != nil else { return }
                    do {
                        try await Task.sleep(for: Self.siriHandOffDelay)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, scenePhase == .active,
                          let action = launchRouter.take() else { return }
                    switch action {
                    case .read: coordinator.startReading()
                    case .write: coordinator.startWriting()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // L'app ne parle ni n'écoute quand elle n'est plus à l'écran.
                _ = launchRouter.take()
                coordinator.stopAll()
            default:
                break
            }
        }
    }

}
