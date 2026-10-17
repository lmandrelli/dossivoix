import AppIntents

/// Raccourcis d'app : disponibles avec Siri dès l'installation, sans aucune configuration,
/// et sans Apple Intelligence.
///
/// Règle d'Apple : chaque phrase contient le nom de l'app, via `\(.applicationName)`.
/// Ce nom est `CFBundleDisplayName`, défini une seule fois par le réglage de build
/// `APP_DISPLAY_NAME` : changer ce réglage met à jour toutes les phrases.
/// Si Siri comprend mal le nom, ajouter des variantes dans `INAlternativeAppNames` (Info.plist).
///
/// Phrases de départ, à ajuster après des essais avec l'utilisatrice.
struct DossivoixShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadTagIntent(),
            phrases: [
                "Lis l'étiquette avec \(.applicationName)",
                "\(.applicationName), lis l'étiquette",
                "Lire un dossier avec \(.applicationName)",
                "Ouvre \(.applicationName) en lecture",
            ],
            shortTitle: "Lire une étiquette",
            systemImageName: "wave.3.right"
        )
        AppShortcut(
            intent: WriteTagIntent(),
            phrases: [
                "Écris une étiquette avec \(.applicationName)",
                "\(.applicationName), écris une étiquette",
                "Nouvelle étiquette avec \(.applicationName)",
                "Ouvre \(.applicationName) en écriture",
            ],
            shortTitle: "Écrire une étiquette",
            systemImageName: "square.and.pencil"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .yellow
}
