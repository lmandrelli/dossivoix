import Foundation

/// Ce que fait la voix de l'app à cet instant. Indépendant de l'état du parcours.
public enum VoiceActivity: Equatable, Sendable {
    case off
    /// Message ou signal sonore en cours.
    case speaking
    /// Micro ouvert.
    case listening
}

/// Une action d'écran. Chaque action a un seul sens, quel que soit l'emplacement.
public enum ScreenAction: Equatable, Sendable, CaseIterable {
    case read
    case write
    /// Terminer la dictée : relecture du texte, puis confirmation. N'écrit jamais.
    case finishDictation
    /// Quitter l'écriture : le brouillon est effacé, aucune étiquette n'est écrite.
    case abandonWriting
    /// « C'est bon » : écrire le nom relu.
    case confirmName
    /// Redire le nom depuis le début.
    case restartDictation
    /// Remplacer le contenu de l'étiquette (seconde passe).
    case replace
    /// Garder l'étiquette telle quelle.
    case keepTag
    /// Répéter la question du contexte et écouter.
    case startVoice
    /// Couper la parole et le micro. Ne valide rien, n'efface rien.
    case stopVoice
}

public struct ControlSlot: Equatable, Sendable {
    public let action: ScreenAction
    public let isEnabled: Bool

    public init(_ action: ScreenAction, enabled: Bool = true) {
        self.action = action
        self.isEnabled = enabled
    }
}

/// Les trois emplacements fixes de l'écran : deux grands boutons de parcours,
/// puis le bouton de la voix. Un bouton désactivé reste visible à sa place.
///
/// | État                     | Grand bouton 1        | Grand bouton 2        | Voix                |
/// |--------------------------|-----------------------|-----------------------|---------------------|
/// | repos / menu vocal       | Lire                  | Écrire                | Voix ↔ Arrêter      |
/// | lecture / écriture NFC   | Lire (inactif)        | Écrire (inactif)      | Voix (inactif)      |
/// | dictée                   | Terminer ¹            | Abandonner            | Voix ↔ Arrêter      |
/// | dictée en pause          | Terminer ²            | Abandonner            | Voix                |
/// | confirmation du nom      | C'est bon ³           | Recommencer           | Voix ↔ Arrêter      |
/// | remplacement             | Remplacer             | Garder                | Voix ↔ Arrêter      |
///
/// Voix ↔ Arrêter : « Arrêter » (avec l'état J'écoute ou Je parle) tant que la voix est active.
/// ¹ actif quand le micro écoute ou qu'un texte est déjà conservé ; ² actif s'il y a du texte ;
/// ³ inactif si le nom ne tient pas sur l'étiquette.
public struct ScreenControls: Equatable, Sendable {
    public let primary: ControlSlot
    public let secondary: ControlSlot
    public let voice: ControlSlot

    public var slots: [ControlSlot] { [primary, secondary, voice] }

    public func allows(_ action: ScreenAction) -> Bool {
        slots.contains { $0.action == action && $0.isEnabled }
    }
}

extension FlowMachine {
    /// Boutons de l'écran pour l'état courant et l'activité de la voix.
    public func controls(voice activity: VoiceActivity) -> ScreenControls {
        let voice: ControlSlot
        if state.isUsingTag {
            voice = ControlSlot(.startVoice, enabled: false)
        } else if activity == .off {
            voice = ControlSlot(.startVoice)
        } else {
            voice = ControlSlot(.stopVoice)
        }

        switch state {
        case .idle, .voiceMenu:
            return ScreenControls(primary: ControlSlot(.read), secondary: ControlSlot(.write), voice: voice)
        case .reading, .writing:
            return ScreenControls(primary: ControlSlot(.read, enabled: false),
                                  secondary: ControlSlot(.write, enabled: false), voice: voice)
        case .askingName:
            let canFinish = activity == .listening || !dictationDraft.isEmpty
            return ScreenControls(primary: ControlSlot(.finishDictation, enabled: canFinish),
                                  secondary: ControlSlot(.abandonWriting), voice: voice)
        case .pausedDictation(let text, _):
            return ScreenControls(primary: ControlSlot(.finishDictation, enabled: !text.isEmpty),
                                  secondary: ControlSlot(.abandonWriting), voice: voice)
        case .confirmingName(let name, _, _):
            return ScreenControls(primary: ControlSlot(.confirmName, enabled: fits(name)),
                                  secondary: ControlSlot(.restartDictation), voice: voice)
        case .confirmingReplace:
            return ScreenControls(primary: ControlSlot(.replace), secondary: ControlSlot(.keepTag), voice: voice)
        }
    }

    /// Événement de la machine pour une action d'écran, hors arrêt de la voix et fin de dictée
    /// pendant l'écoute, qui dépendent aussi du micro (voir FlowCoordinator).
    public static func event(for action: ScreenAction, partial: String = "") -> FlowEvent {
        switch action {
        case .read: .startReading
        case .write: .startWriting
        case .finishDictation: .finishDictation(partial: partial)
        case .abandonWriting: .abandonWriting
        case .confirmName, .replace: .screenAnswer(.yes)
        case .restartDictation: .screenAnswer(.restart)
        case .keepTag: .screenAnswer(.no)
        case .startVoice: .resumeVoice
        case .stopVoice: .stopVoice(partial: partial)
        }
    }
}
