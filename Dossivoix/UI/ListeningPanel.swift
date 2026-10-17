import SwiftUI

/// Panneau « J'écoute » : monte du bas de l'écran pendant que le micro est ouvert,
/// avec une bulle de parole dont les barres s'animent (le même motif que l'icône).
///
/// C'est le seul élément animé de l'app. Il occupe une zone réservée en permanence,
/// donc rien d'autre ne bouge quand il apparaît. Avec « Réduire les animations »,
/// il apparaît en fondu et les barres restent immobiles.
struct ListeningPanel: View {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if isVisible {
                panel
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8),
                   value: isVisible)
        // Pas d'annonce VoiceOver : le signal sonore « j'écoute » suffit,
        // et VoiceOver ne doit pas parler pendant que le micro est ouvert.
        .accessibilityHidden(true)
    }

    private var panel: some View {
        HStack(spacing: 20) {
            // Bulle blanche à contour noir (pas d'aplat noir, qui deviendrait blanc une fois inversé).
            SpeechBubble()
                .fill(.white)
                .overlay(SpeechBubble().stroke(.black, style: StrokeStyle(lineWidth: 4, lineJoin: .round)))
                .frame(width: 132, height: 72)
                .overlay {
                    WaveBars(isAnimated: !reduceMotion)
                        .foregroundStyle(.black)
                        .frame(width: 92, height: 44)
                        .offset(y: -3)
                }
            Text("J'écoute…")
                .font(.system(.title, weight: .heavy))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.black, lineWidth: 4))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// Barres de l'onde sonore (motif « voix » de l'icône), animées en douceur.
struct WaveBars: View {
    let isAnimated: Bool

    /// Hauteurs de repos, identiques à celles de l'icône.
    private static let restHeights: [Double] = [0.3, 0.6, 0.45, 1, 0.7, 0.4, 0.25]

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let count = Double(Self.restHeights.count)
                let barWidth = geometry.size.width / (count * 1.6 - 0.6)
                HStack(alignment: .center, spacing: barWidth * 0.6) {
                    ForEach(Self.restHeights.indices, id: \.self) { index in
                        Capsule()
                            .frame(width: barWidth,
                                   height: max(barWidth, geometry.size.height * height(index, time)))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// Hauteur relative d'une barre : oscille autour de sa hauteur de repos, avec un décalage par barre.
    private func height(_ index: Int, _ time: TimeInterval) -> Double {
        let rest = Self.restHeights[index]
        guard isAnimated else { return rest }
        let wave = 0.5 + 0.5 * sin(time * 5 + Double(index) * 1.3)
        return rest * (0.45 + 0.55 * wave)
    }
}

/// Bulle de parole : pilule avec une petite queue en bas à gauche.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let bodyHeight = rect.height * 0.86
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight)
        let bubble = Path(roundedRect: body, cornerRadius: bodyHeight / 2)
        // Queue : petit triangle sous la bulle, côté gauche, qui part de l'intérieur de la bulle.
        var tail = Path()
        tail.move(to: CGPoint(x: rect.minX + rect.width * 0.40, y: body.maxY - 10))
        tail.addLine(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY))
        tail.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: body.maxY - 10))
        tail.closeSubpath()
        // Fusion en une seule forme : contour continu, sans trait à la jonction.
        return bubble.union(tail)
    }
}

#Preview {
    VStack {
        Spacer()
        ListeningPanel(isVisible: true).frame(height: 112)
    }
}
