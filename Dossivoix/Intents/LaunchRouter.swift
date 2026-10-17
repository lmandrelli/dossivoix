import Observation

/// Parcours demandé au lancement (par Siri, Raccourcis ou Spotlight).
enum LaunchAction: Hashable {
    case read
    case write
}

/// Transmet à l'app le parcours demandé par un App Intent.
///
/// L'intent s'exécute parfois avant que l'écran soit prêt (lancement à froid) :
/// la demande est gardée ici jusqu'à ce que l'app soit active, puis consommée une seule fois.
@MainActor
@Observable
final class LaunchRouter {
    static let shared = LaunchRouter()

    private(set) var pending: LaunchAction?

    func request(_ action: LaunchAction) {
        pending = action
    }

    /// Récupère la demande en attente et l'efface.
    func take() -> LaunchAction? {
        defer { pending = nil }
        return pending
    }
}
