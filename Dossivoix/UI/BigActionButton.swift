import SwiftUI

/// Très grand bouton lisible avec Dynamic Type, VoiceOver et l'inversion intelligente.
///
/// Fond blanc, contour épais et texte noirs. Aucun aplat noir : avec l'inversion intelligente,
/// le bouton devient noir avec un contour et un texte blancs, comme tout le reste de l'écran.
/// (Un bouton noir deviendrait au contraire un bloc blanc éblouissant une fois inversé.)
struct BigActionButton: View {
    let title: String
    let systemImage: String
    /// Libellé lu par VoiceOver (plus explicite que le titre affiché).
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.largeTitle, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.black, lineWidth: 6))
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(StillButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// Bouton sans animation : seul un léger grisé signale l'appui.
struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .transaction { $0.animation = nil }
    }
}
