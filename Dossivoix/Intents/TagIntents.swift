import AppIntents

/// « Lire une étiquette » : ouvre l'app et lance tout de suite la lecture, sans toucher l'écran.
struct ReadTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Lire une étiquette"
    static let description = IntentDescription("Ouvre Dossivoix et annonce le nom du dossier inscrit sur une étiquette NFC.")
    /// Le NFC ne fonctionne qu'app ouverte, au premier plan.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.request(.read)
        return .result()
    }
}

/// « Écrire une étiquette » : ouvre l'app et lance tout de suite l'écriture guidée à la voix.
struct WriteTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Écrire une étiquette"
    static let description = IntentDescription("Ouvre Dossivoix et écrit sur une étiquette NFC le nom de dossier que vous dictez.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.request(.write)
        return .result()
    }
}
