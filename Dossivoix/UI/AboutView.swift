import SwiftUI

struct AboutView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Largeur de lecture confortable sur iPad ou en paysage ; le texte reste aligné à gauche.
    private let readingWidth: CGFloat = 640

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                introduction
                usageSection
                helpSection
                privacySection
            }
            .font(.body)
            .foregroundStyle(palette.ink)
            .frame(maxWidth: readingWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(palette.paper)
        .buttonStyle(StillButtonStyle())
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dossivoix")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h1)
            paragraph("Identifiez vos dossiers papier avec des étiquettes NFC, à la voix ou au clavier.")
            paragraph("Gratuite, sans compte et sans publicité.")
        }
    }

    private var usageSection: some View {
        section("Utiliser l'app") {
            subsection("Avec Siri") {
                paragraph("Dites par exemple : « Lis mon dossier avec Dossivoix » ou « Crée une étiquette avec Dossivoix ».")
                paragraph("Prononcez « Dossi voix ». Aucun raccourci à créer : Siri ouvre l'app et démarre le parcours.")
                paragraph("Siri peut vous demander de déverrouiller l'iPhone.")
            }
            subsection("Remplacer une étiquette") {
                paragraph("Après confirmation, approchez à nouveau l'étiquette choisie.")
                paragraph("L'app vérifie son contenu, pas son identité physique : deux étiquettes portant exactement les mêmes données ne peuvent pas être distinguées.")
            }
        }
    }

    private var helpSection: some View {
        section("Aide et dépannage") {
            subsection("Aide et contact") {
                Link(destination: AppIdentity.supportURL) {
                    actionLabel("Consulter l'aide", icon: "questionmark.circle", external: true)
                }
                Link(destination: AppIdentity.contactURL) {
                    actionLabel("Contacter le développeur", icon: "envelope", external: true)
                }
                paragraph("Par e-mail : luca.mandrelli@icloud.com")
                    .textSelection(.enabled)
            }
            subsection("Un problème avec une étiquette ?") {
                paragraph("Le diagnostic permet de consulter les dernières lectures et de partager un rapport si vous le souhaitez.")
                paragraph(Text("\(Text("Attention :").bold()) les rapports peuvent contenir le nom et le contenu des étiquettes. Utilisez une étiquette d'essai sans information confidentielle."))
                NavigationLink(value: MainDestination.diagnostic) {
                    actionLabel("Ouvrir le diagnostic", icon: "doc.text.magnifyingglass", external: false)
                }
                .accessibilityHint("Affiche les rapports des étiquettes lues. Rien n'est envoyé automatiquement.")
                NavigationLink(value: MainDestination.eraseTag) {
                    actionLabel("Vider une étiquette", icon: "eraser", external: false)
                }
                .accessibilityHint("Fonction avancée. Supprime le contenu NDEF après confirmation.")
            }
        }
    }

    private var privacySection: some View {
        section("Confidentialité") {
            paragraph("Aucun enregistrement audio n'est conservé.")
            paragraph("La reconnaissance vocale utilise le service d'Apple, sur l'iPhone quand il le permet, sinon avec un traitement par Apple.")
            paragraph("Le clavier reste utilisable sans autoriser le micro.")
            Link(destination: AppIdentity.privacyURL) {
                actionLabel("Lire la politique de confidentialité", icon: "hand.raised", external: true)
            }
        }
    }

    // MARK: - Composants

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h2)
            }
            content()
        }
    }

    private func subsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h3)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        paragraph(Text(text))
    }

    private func paragraph(_ text: Text) -> some View {
        text
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionLabel(_ title: String, icon: String, external: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: icon)
                    .accessibilityHidden(true)
            }
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.body.bold())
                    .accessibilityHidden(true)
            }
        }
        .font(.headline)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.ink, lineWidth: 3))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
