import SwiftUI

/// Les deux seules couleurs de l'app : l'encre (texte, contours) et le papier (fonds).
///
/// - Thème clair : noir sur blanc. Avec l'inversion intelligente, l'écran apparaît en blanc sur noir.
/// - Thème foncé : blanc sur noir.
/// - Thème foncé + inversion intelligente (rare) : l'app repasse en noir sur blanc pour que,
///   une fois inversée, elle reste en blanc sur noir.
///
/// Jamais d'aplat de la couleur d'encre : il deviendrait un bloc éblouissant une fois inversé.
struct Palette: Equatable {
    let ink: Color
    let paper: Color

    static let blackOnWhite = Palette(ink: .black, paper: .white)
    static let whiteOnBlack = Palette(ink: .white, paper: .black)

    static func current(colorScheme: ColorScheme, invertColors: Bool) -> Palette {
        colorScheme == .dark && !invertColors ? .whiteOnBlack : .blackOnWhite
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.blackOnWhite
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Choisit la palette selon le thème et l'inversion intelligente, et la transmet aux vues.
private struct AdaptivePalette: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityInvertColors) private var invertColors

    func body(content: Content) -> some View {
        let palette = Palette.current(colorScheme: colorScheme, invertColors: invertColors)
        content
            .environment(\.palette, palette)
            .tint(palette.ink)
    }
}

extension View {
    func adaptivePalette() -> some View {
        modifier(AdaptivePalette())
    }
}
