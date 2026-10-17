import Foundation

/// Identité de l'app, centralisée.
///
/// Le nom affiché vient d'un seul endroit : le réglage de build `APP_DISPLAY_NAME`
/// (cible Dossivoix → Build Settings), recopié dans `CFBundleDisplayName`.
/// Les phrases Siri utilisent automatiquement ce nom via `\(.applicationName)`.
enum AppIdentity {
    static let privacyURL = URL(string: "https://lmandrelli.github.io/dossivoix/privacy")!
    static let supportURL = URL(string: "https://lmandrelli.github.io/dossivoix/support")!
    static let contactURL = URL(string: "https://github.com/lmandrelli/dossivoix/issues")!
    /// Nom prononcé et affiché par l'app.
    static let name: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Dossivoix"
}
