---
title: Politique de confidentialité – Dossivoix
---

# Politique de confidentialité de Dossivoix

*Dernière mise à jour : 11 novembre 2026.*

Dossivoix est une application gratuite et open source, publiée par un particulier
(Luca Mandrelli). **Aucune donnée personnelle n'est collectée automatiquement par le
développeur.** Les traitements par les services Apple et le partage volontaire sont décrits ci-dessous.

## Ce que l'application ne fait pas

- Elle ne crée aucun compte et ne demande aucune identité.
- Elle n'envoie automatiquement aucune donnée au développeur : pas de serveur applicatif,
  pas de statistiques d'utilisation, pas de publicité, pas de suivi (« tracking »).
- Dossivoix ne conserve pas de fichier audio ni d'historique persistant des étiquettes sur l'iPhone.

## Ce qui se passe sur votre iPhone

**Étiquettes NFC.** Le contenu des étiquettes est lu et écrit uniquement à votre demande,
pendant la session NFC affichée par iOS. Les dernières étiquettes lues sont gardées en
mémoire, pour l'écran « Diagnostic » (20 lectures au maximum), jusqu'à la fin du processus
de l'application. Le simple passage en arrière-plan ne les efface pas. Dossivoix ne les
stocke pas dans un fichier ou une base de données sur l'iPhone.

**Micro et reconnaissance vocale.** Le micro est ouvert pendant les écoutes de l'application :
dictée du texte d'une étiquette, choix d'une action ou réponse à une confirmation.
L'indicateur **J'écoute** signale cette activité. **Annuler** coupe la voix et le micro.
Une session de dictée dure au maximum 55 secondes ; iOS peut l'interrompre plus tôt. La reconnaissance vocale est faite par iOS (framework Speech d'Apple) :

- quand l'iPhone le permet, elle se fait **entièrement sur l'appareil** ;
- sinon, iOS peut transmettre l'audio à Apple pour le transcrire, selon la
  [politique de confidentialité d'Apple](https://www.apple.com/legal/privacy/fr-ww/).
  Dossivoix reçoit le texte reconnu et ne conserve pas d'enregistrement audio.
  Les règles de traitement et de conservation des services Apple relèvent d'Apple ;
  Dossivoix ne garantit pas leur absence de conservation.

**Brouillon dicté.** Le texte déjà reconnu reste en mémoire pendant le parcours d'écriture,
y compris lorsque vous mettez la dictée en pause. Il n'est pas enregistré dans un fichier.
Une fermeture complète de l'app fait perdre ce brouillon.

**Synthèse vocale.** Les phrases sont prononcées par la voix française d'iOS, sur l'appareil.

**Siri.** Les phrases Siri (« Lis l'étiquette avec Dossivoix »…) sont traitées par Siri,
selon la politique de confidentialité d'Apple. Siri ouvre l'application et lui demande
de démarrer une lecture ou une écriture.

## Partage volontaire

L'écran « Diagnostic » (accessible par **À propos → Dépannage → Diagnostic**)
permet de **partager vous-même** le détail technique d'une étiquette
(par message ou e-mail, par exemple), avec la feuille de partage d'iOS. Rien n'est envoyé
sans votre action, et le destinataire est celui que vous choisissez.
Ces rapports peuvent contenir le nom et le contenu complet de vos étiquettes : relisez-les
avant de les partager. Les copies partagées suivent les règles du service destinataire.

Aucun réglage de diagnostic n'est enregistré. Son historique temporaire reste en mémoire
jusqu'à la fin du processus de l'application.

## Autorisations demandées

| Autorisation | Pourquoi |
|---|---|
| NFC | Lire et écrire les étiquettes collées sur vos dossiers. |
| Micro | Entendre le texte dicté, le choix d'une action ou une réponse pendant l'écoute. |
| Reconnaissance vocale | Transformer votre voix en texte pour comprendre ces réponses. |

Vous pouvez retirer les autorisations **micro et reconnaissance vocale** dans les Réglages
d'iOS. La lecture NFC reste utilisable sans ces autorisations ; l'écriture d'un nom demande la dictée.
La session NFC est visible à l'écran et peut être annulée depuis la feuille système.

## Conservation et suppression

Fermer complètement l'application libère les diagnostics gardés en mémoire. Dossivoix
n'enregistre pas d'historique local persistant. Désinstaller l'app ne modifie pas les
étiquettes NFC déjà écrites. Le développeur ne dispose d'aucun historique serveur à effacer.
Pour un rapport partagé, demandez sa suppression au destinataire concerné. Si vous avez
publié un ticket GitHub, vous pouvez modifier son contenu ou demander sa suppression au développeur.

## Enfants

Le développeur ne collecte automatiquement aucune donnée, quel que soit l'âge de l'utilisateur.
Les traitements Apple et les partages volontaires décrits plus haut s'appliquent également.

## Modifications

Toute modification de cette politique sera publiée sur cette page et visible dans
l'historique du [dépôt GitHub](https://github.com/lmandrelli/dossivoix).

## Contact

Pour toute question, écrivez à [luca.mandrelli@icloud.com](mailto:luca.mandrelli@icloud.com)
ou [ouvrez un ticket sur GitHub](https://github.com/lmandrelli/dossivoix/issues).
Un compte GitHub est nécessaire. Les tickets sont publics : n'y publiez pas de données personnelles
ni de noms de dossiers confidentiels. Cette politique et le contact sont accessibles dans l'app,
via **À propos**.

---

## English summary

Dossivoix's developer **does not automatically collect personal data**. The app has no account,
analytics, ads, tracking, or application server. Up to 20 NFC readings are kept in memory for
the Diagnostic screen until the app process ends; entering the background does not erase them.
Dossivoix does not store an audio recording or tag history on disk. The microphone is used only
during dictation and voice interactions (a dictation session lasts up to 55 seconds); speech recognition is performed by iOS,
on device when available, otherwise audio may be processed by Apple under Apple's privacy
policy, including Apple's retention rules. Diagnostic is available through “À propos” →
“Dépannage” → “Diagnostic” without a saved setting. Reports leave the device only if the user
shares them via the iOS share sheet; shared copies are subject to the recipient's practices.
Privacy and support links are available in the app's “À propos” screen.


[Accueil](index.html) · [Assistance](support.html)
