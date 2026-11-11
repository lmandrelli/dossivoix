import SwiftUI

/// Très grand bouton lisible avec Dynamic Type, VoiceOver et l'inversion intelligente.
///
/// Fond « papier », contour épais et texte « encre » (voir Palette). Aucun aplat d'encre :
/// avec l'inversion intelligente, il deviendrait un bloc blanc éblouissant.
struct BigActionButton: View {
    let title: String
    let systemImage: String
    /// Libellé lu par VoiceOver (plus explicite que le titre affiché).
    let accessibilityLabel: String
    let accessibilityHint: String
    var fitsAvailableSpace = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if fitsAvailableSpace {
                    HStack(spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(size: 32, weight: .heavy))
                            .accessibilityHidden(true)
                        Text(title)
                    }
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
            .font(.system(.largeTitle, weight: .heavy))
            .lineLimit(fitsAvailableSpace ? 1 : (dynamicTypeSize.isAccessibilitySize ? nil : 2))
            .minimumScaleFactor(fitsAvailableSpace ? 0.3 : (dynamicTypeSize.isAccessibilitySize ? 1 : 0.5))
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize && !fitsAvailableSpace)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(palette.paper, in: RoundedRectangle(cornerRadius: 28))
            // Inactif : contour en tirets en plus de l'opacité, pour ne pas dépendre du contraste seul.
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(
                palette.ink, style: StrokeStyle(lineWidth: 6, dash: isEnabled ? [] : [14, 10])))
            .opacity(isEnabled ? 1 : 0.35)
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
