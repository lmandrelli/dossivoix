import SwiftUI

/// Les deux seules couleurs de l'app : l'encre (texte, contours) et le papier (fonds).
///
/// - Thème clair : noir sur blanc. Avec l'inversion intelligente, iOS inverse l'app :
///   elle apparaît en blanc sur noir.
/// - Thème foncé : blanc sur noir. Avec l'inversion intelligente, iOS épargne les apps
///   au style sombre (« sauf […] certaines apps qui utilisent un style de couleur sombre ») :
///   l'app reste en blanc sur noir.
///
/// Jamais d'aplat de la couleur d'encre : en thème clair inversé, il deviendrait un bloc
/// blanc éblouissant.
struct Palette: Equatable {
    let ink: Color
    let paper: Color

    static let blackOnWhite = Palette(ink: .black, paper: .white)
    static let whiteOnBlack = Palette(ink: .white, paper: .black)

    static func current(colorScheme: ColorScheme) -> Palette {
        colorScheme == .dark ? .whiteOnBlack : .blackOnWhite
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

/// Choisit la palette selon le thème de l'iPhone, et la transmet aux vues.
private struct AdaptivePalette: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = Palette.current(colorScheme: colorScheme)
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
