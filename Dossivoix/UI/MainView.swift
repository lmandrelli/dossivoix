import SwiftUI
import DossivoixCore

/// Écran principal (squelette de l'étape 0).
/// Les deux grands boutons « Lire » et « Écrire » seront branchés aux étapes suivantes.
struct MainView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text(AppIdentity.name)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("En construction")
                .font(.title2)
            Text("Capacité d'une NTAG 213 : \(TagCapacity.ntag213MaxMessageLength) octets")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    MainView()
}
