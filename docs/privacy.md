---
title: Politique de confidentialité – Dossivoix
---

# Politique de confidentialité de Dossivoix

*Dernière mise à jour : 17 octobre 2026 — brouillon à relire avant publication.*

Dossivoix est une application gratuite et open source, publiée par un particulier
(Luca Mandrelli), sans activité commerciale. Elle a été conçue pour ne collecter
**aucune donnée personnelle**.

## Ce que l'application ne fait pas

- Elle ne crée aucun compte et ne demande aucune identité.
- Elle n'envoie aucune donnée au développeur ni à un service tiers : pas de serveur,
  pas de statistiques d'utilisation, pas de publicité, pas de suivi (« tracking »).
- Elle n'enregistre ni votre voix, ni le contenu de vos étiquettes.

## Ce qui se passe sur votre iPhone

**Étiquettes NFC.** Le contenu des étiquettes est lu et écrit uniquement à votre demande,
pendant la session NFC affichée par iOS. Les dernières étiquettes lues sont gardées en
mémoire, pour l'écran « Diagnostic », jusqu'à la fermeture de l'application. Elles ne sont
jamais enregistrées sur le stockage de l'iPhone.

**Micro et reconnaissance vocale.** Le micro n'est ouvert que pendant de courtes écoutes,
juste après une question de l'application (le nom d'un dossier, ou une réponse comme
« oui » ou « non »). La reconnaissance vocale est faite par iOS (framework Speech d'Apple) :

- quand l'iPhone le permet, elle se fait **entièrement sur l'appareil** ;
- sinon, iOS peut transmettre l'audio à Apple pour le transcrire, selon la
  [politique de confidentialité d'Apple](https://www.apple.com/legal/privacy/fr-ww/).
  Dossivoix n'a pas accès à ces échanges et n'en conserve rien.

**Synthèse vocale.** Les phrases sont prononcées par la voix française d'iOS, sur l'appareil.

**Siri.** Les phrases Siri (« Lis l'étiquette avec Dossivoix »…) sont traitées par Siri,
selon la politique de confidentialité d'Apple. Siri ne fait qu'ouvrir l'application.

## Partage volontaire

L'écran « Diagnostic » (affiché seulement si vous activez Réglages → Dossivoix → Mode diagnostic)
permet de **partager vous-même** le détail technique d'une étiquette
(par message ou e-mail, par exemple), avec la feuille de partage d'iOS. Rien n'est envoyé
sans votre action, et le destinataire est celui que vous choisissez.

Le seul réglage enregistré par l'application est l'état de l'interrupteur « Mode diagnostic »,
conservé sur l'iPhone.

## Autorisations demandées

| Autorisation | Pourquoi |
|---|---|
| NFC | Lire et écrire les étiquettes collées sur vos dossiers. |
| Micro | Entendre le nom d'un dossier ou votre réponse, pendant les courtes questions. |
| Reconnaissance vocale | Transformer votre voix en texte pour comprendre ces réponses. |

Vous pouvez retirer ces autorisations à tout moment dans **Réglages → Dossivoix**.
L'application reste alors utilisable avec l'écran et le clavier.

## Enfants

L'application ne collecte aucune donnée, y compris auprès des enfants.

## Modifications

Toute modification de cette politique sera publiée sur cette page et visible dans
l'historique du [dépôt GitHub](https://github.com/lmandrelli/dossivoix).

## Contact

Pour toute question : [ouvrir un ticket sur GitHub](https://github.com/lmandrelli/dossivoix/issues).

---

## English summary

Dossivoix collects **no personal data**. It has no account, no analytics, no ads, no tracking,
and no server. NFC tag contents are read or written only on request and kept in memory (never
on disk) for the in-app Diagnostic screen until the app is closed. The microphone is used only
during short listening periods right after a question; speech recognition is performed by iOS,
on device when available, otherwise audio may be processed by Apple under Apple's privacy
policy. Diagnostic reports leave the device only if the user shares them via the iOS share sheet.
