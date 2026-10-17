import UIKit

/// Parole confiée à VoiceOver (annonces UIAccessibility).
///
/// Variante à essayer si la synthèse de l'app entre en conflit avec VoiceOver :
/// voir `VoiceSettings.usesVoiceOverAnnouncements`. Une annonce ne peut pas être coupée,
/// et VoiceOver ne signale pas toujours sa fin : on attend la notification de fin,
/// avec un délai maximal estimé d'après la longueur du texte.
@MainActor
final class VoiceOverAnnouncer: SpeechOutput {
    func speak(_ text: String) async {
        let announcement = NSAttributedString(string: text, attributes: [
            // Attendre la fin de ce que VoiceOver dit déjà, au lieu de l'interrompre.
            .accessibilitySpeechQueueAnnouncement: true,
            .accessibilitySpeechLanguage: SynthesizerSpeechOutput.language,
        ])
        UIAccessibility.post(notification: .announcement, argument: announcement)
        await waitForAnnouncementEnd(of: text)
    }

    func stop() {
        // Impossible d'interrompre une annonce VoiceOver.
    }

    private func waitForAnnouncementEnd(of text: String) async {
        // Environ 15 caractères par seconde, plus une marge.
        let timeout = Duration.seconds(2 + Double(text.count) / 15)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let finished = NotificationCenter.default.notifications(
                    named: UIAccessibility.announcementDidFinishNotification
                )
                for await notification in finished {
                    let announced = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
                    if announced == text { return }
                }
            }
            group.addTask { try? await Task.sleep(for: timeout) }
            // Le premier des deux qui se termine suffit.
            await group.next()
            group.cancelAll()
        }
    }
}
