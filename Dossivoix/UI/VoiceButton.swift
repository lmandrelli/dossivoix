import SwiftUI
import DossivoixCore

/// Indicateur libre à gauche ; commande Voix / Annuler fixe à droite.
/// Seul le bouton est tactile. Le fond reste celui de la page.
struct VoiceButton: View {
    let slot: ControlSlot
    let activity: VoiceActivity
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isStop: Bool { slot.action == .stopVoice }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if activity != .off { status }
                else { Color.clear.accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            Button(action: action) {
                label(isStop ? "Annuler" : "Voix", systemImage: isStop ? "stop.fill" : "mic.fill")
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                        palette.ink, style: StrokeStyle(lineWidth: 4, dash: slot.isEnabled ? [] : [10, 7])))
                    .opacity(slot.isEnabled ? 1 : 0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .buttonStyle(StillButtonStyle())
            .disabled(!slot.isEnabled)
            .accessibilityLabel(isStop ? "Annuler la voix" : "Voix")
            .accessibilityHint(isStop
                ? "Coupe la parole et le micro. Le texte est conservé, rien n'est validé."
                : "Répète la consigne et écoute votre réponse.")
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            Group {
                if activity == .listening {
                    WaveBars(isAnimated: !reduceMotion).frame(width: 30, height: 24)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .accessibilityHidden(true)
            Text(activity == .listening ? "J’écoute" : "Je parle")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Barres de l'onde sonore (motif « voix » de l'icône), animées en douceur.
/// Immobiles avec « Réduire les animations ».
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

    private func height(_ index: Int, _ time: TimeInterval) -> Double {
        let rest = Self.restHeights[index]
        guard isAnimated else { return rest }
        let wave = 0.5 + 0.5 * sin(time * 5 + Double(index) * 1.3)
        return rest * (0.45 + 0.55 * wave)
    }
}
