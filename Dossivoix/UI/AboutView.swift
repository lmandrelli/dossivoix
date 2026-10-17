import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("Dossivoix") {
                Text("Identifiez vos dossiers papier avec des étiquettes NFC, à la voix ou au clavier.")
                Text("Application gratuite, sans compte, sans publicité et sans suivi publicitaire.")
            }
            Section("Confidentialité et assistance") {
                Link("Politique de confidentialité", destination: AppIdentity.privacyURL)
                Link("Aide et assistance", destination: AppIdentity.supportURL)
                Link("Contacter le développeur", destination: AppIdentity.contactURL)
                Text("Le contact se fait par un ticket GitHub. Un compte GitHub est nécessaire. Ne publiez pas de données personnelles ni de contenu confidentiel dans un ticket public.")
                    .font(.footnote)
            }
            Section("Votre voix") {
                Text("Dossivoix ne conserve pas d'enregistrement audio. La reconnaissance utilise le service Speech d'Apple : sur l'iPhone quand il le permet, sinon avec un traitement par Apple. Vous pouvez utiliser le clavier sans autoriser la reconnaissance vocale.")
            }
            Section("Remplacer une étiquette") {
                Text("Après confirmation, approchez à nouveau l'étiquette choisie. L'app vérifie que son contenu correspond à celui lu auparavant. Deux étiquettes portant exactement le même contenu ne peuvent pas être distinguées.")
            }
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
