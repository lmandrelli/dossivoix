import SwiftUI

/// Point d'entrée de l'app.
@main
struct DossivoixApp: App {
    @State private var coordinator = FlowCoordinator.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            // L'app ne parle pas quand elle n'est plus à l'écran.
            if phase == .background {
                coordinator.stopSpeaking()
            }
        }
    }
}
