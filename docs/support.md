---
title: Assistance – Dossivoix
---

# Assistance Dossivoix

## Démarrer

1. Ouvrez Dossivoix. Le micro et la reconnaissance vocale sont demandés à la première
   écoute ; vous pouvez les refuser et utiliser le bouton **Clavier**.
2. Dites à Siri : **« Lis l'étiquette avec Dossivoix »**, puis approchez le haut de
   l'iPhone de l'étiquette collée sur le dossier. Le nom du dossier est annoncé.
3. Pour écrire une étiquette : **« Écris une étiquette avec Dossivoix »**, dites le nom
   du dossier, confirmez par « oui », puis approchez l'étiquette.

Autres phrases pour **lire** : « Lis étiquette Dossivoix »,
« Lis l'étiquette Dossivoix », « Dossivoix, lis l'étiquette »,
« Lire un dossier avec Dossivoix », « Ouvre Dossivoix en lecture »,
« Lis mon dossier avec Dossivoix », « Lis cette étiquette avec Dossivoix »,
« Identifie ce dossier avec Dossivoix », « Lis avec Dossivoix ».

Autres phrases pour **écrire** : « Dossivoix, écris une étiquette »,
« Nouvelle étiquette avec Dossivoix », « Ouvre Dossivoix en écriture »,
« Crée une étiquette avec Dossivoix », « Étiquette un dossier avec Dossivoix »,
« Écris avec Dossivoix ». Cela fait 17 phrases proposées au total : 10 pour lire et 7 pour
écrire. Aucun raccourci n'est à créer dans l'app Raccourcis. Siri peut aussi comprendre des
formulations proches, mais la reconnaissance dépend de la voix et des conditions d'écoute.

Réponses comprises pendant les questions : *oui*, *non*, *recommencer*, *annuler*,
*encore* (lire une autre étiquette), *écrire*.
Pour confirmer un remplacement, répondez simplement **oui** ou **non**.
Une phrase négative ou ambiguë ne vaut pas autorisation de remplacement.

Après une confirmation, présentez de nouveau l'étiquette choisie. Dossivoix vérifie
son contenu, pas son identité physique : deux étiquettes au contenu identique ne sont
pas distinguées. N'approchez qu'une seule étiquette à la fois.

## Questions fréquentes

**La voix est robotique.**
Téléchargez une voix française de meilleure qualité, gratuite : Réglages → Accessibilité →
Contenu énoncé → Voix → Français, puis choisissez une voix « Améliorée » ou « Premium ».
Dossivoix l'utilise automatiquement. Avec VoiceOver actif, c'est la voix de VoiceOver qui est utilisée.

**L'étiquette n'est pas détectée.**
Approchez le *haut* de l'iPhone (près de l'appareil photo), à un ou deux centimètres,
et gardez-le immobile une seconde. Les coques épaisses ou métalliques gênent la lecture.

**« L'étiquette a été retirée trop tôt ».**
Laissez l'iPhone contre l'étiquette jusqu'au signal sonore de fin.

**« Cette étiquette est verrouillée ».**
L'étiquette a été protégée en écriture par un autre appareil : elle peut encore être lue,
mais plus modifiée. Dossivoix ne verrouille jamais une étiquette.

**Le nom est trop long.**
Une étiquette NTAG 213 contient environ 110 caractères (les lettres accentuées comptent double).

**Siri ne comprend pas « Dossivoix ».**
Essayez de prononcer « Dossi voix » et une phrase courte comme « Lis avec Dossivoix » ou
« Écris avec Dossivoix ». Le nom prononcé « Dossi voix » est configuré dans l'app, mais son
effet sur la reconnaissance par Siri doit être vérifié à la voix sur votre iPhone.
Lors d'un essai, « Lis etiquette dossivoix » a ouvert Apple Music : les nouvelles variantes
sans « avec » restent à retester à la voix. Si Siri ouvre une autre app, ouvrez Dossivoix
directement et utilisez ses grands boutons « Lire » et « Écrire ».

**Quels contenus d’étiquettes sont pris en charge ?**
Dossivoix lit les enregistrements NFC NDEF texte (`text/plain` et RTD_TEXT).
Elle écrit deux enregistrements `text/plain` : le marqueur `TEXT`, puis le texte suivi
d’un espace. Les contenus audio ne sont pas pris en charge.

**Une étiquette annonce « format non reconnu ».**
Dans Dossivoix, ouvrez **À propos → Dépannage → Diagnostic**, touchez
« Partager ce rapport » et
joignez-le à votre demande d'aide : il permettra d'étudier ce format.
Le rapport contient les données de l'étiquette ; utilisez une étiquette d'essai sans information confidentielle.

## Nous contacter

Pour obtenir de l'aide sans compte GitHub, écrivez à
[luca.mandrelli@icloud.com](mailto:luca.mandrelli@icloud.com).

[Ouvrir un ticket sur GitHub](https://github.com/lmandrelli/dossivoix/issues)
(un compte GitHub gratuit est nécessaire).
Ces liens sont aussi disponibles dans l'app, via **À propos**. Les tickets sont publics :
ne publiez pas d'informations personnelles ou confidentielles.

Voir aussi la [politique de confidentialité](privacy.md).
