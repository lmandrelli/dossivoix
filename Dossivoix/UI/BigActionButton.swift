import SwiftUI

/// Très grand bouton à fort contraste, lisible avec Dynamic Type et VoiceOver.
struct BigActionButton: View {
    let title: String
    let systemImage: String
    /// Libellé lu par VoiceOver (plus explicite que le titre affiché).
    let accessibilityLabel: String
    let accessibilityHint: String
    let foreground: Color
    let background: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.largeTitle, weight: .heavy))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 28))
                .overlay(
                    // Bordure pour rester visible même sur un fond de même teinte.
                    RoundedRectangle(cornerRadius: 28).strokeBorder(foreground, lineWidth: 3)
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// Couleurs à fort contraste (rapport supérieur à 12:1 dans les deux cas).
enum HighContrast {
    /// Noir sur jaune, pour « Lire ».
    static let readForeground = Color.black
    static let readBackground = Color(red: 1.0, green: 0.85, blue: 0.0)
    /// Blanc sur bleu nuit, pour « Écrire ».
    static let writeForeground = Color.white
    static let writeBackground = Color(red: 0.0, green: 0.12, blue: 0.38)
}
