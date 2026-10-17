import SwiftUI

/// Très grand bouton en noir et blanc, lisible avec Dynamic Type, VoiceOver et l'inversion intelligente.
/// - `.filled` : fond noir, texte blanc (action principale) ;
/// - `.outlined` : fond blanc, contour épais et texte noirs (seconde action).
struct BigActionButton: View {
    enum Style {
        case filled
        case outlined
    }

    let title: String
    let systemImage: String
    /// Libellé lu par VoiceOver (plus explicite que le titre affiché).
    let accessibilityLabel: String
    let accessibilityHint: String
    let style: Style
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color { style == .filled ? .white : .black }
    private var background: Color { style == .filled ? .black : .white }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.largeTitle, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.black, lineWidth: 5))
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(StillButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// Bouton sans animation : seul un léger assombrissement signale l'appui.
struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.15 : 0)
            .transaction { $0.animation = nil }
    }
}
