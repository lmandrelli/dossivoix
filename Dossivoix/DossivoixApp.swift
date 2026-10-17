import SwiftUI

/// Point d'entrée de l'app.
@main
struct DossivoixApp: App {
    @State private var coordinator = FlowCoordinator.live()

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator)
        }
    }
}
