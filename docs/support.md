---
title: Assistance — Dossivoix
---

# Assistance Dossivoix

## Lire une étiquette

Touchez **Lire**, puis approchez le haut de l'iPhone de l'étiquette NFC.
Dossivoix annonce le texte à voix haute. Pour lire une autre étiquette,
touchez de nouveau **Lire**, ou utilisez **Voix** et dites « lire ».

## Écrire une étiquette

1. Touchez **Écrire** et autorisez le micro et la reconnaissance vocale si iOS le demande.
2. Dictez le nom ou le texte du dossier. Vous pouvez faire des pauses.
3. Dites **« terminer la dictée »** ou touchez **Terminer**.
4. Dossivoix relit : **« J'ai compris : … C'est bon ? »**. Vérifiez le texte,
   puis dites **« oui »** ou touchez **C'est bon**. Pour le redire depuis le début,
   touchez **Recommencer**.
5. Approchez l'étiquette et maintenez l'iPhone près d'elle jusqu'à la fin de l'écriture.

Si l'étiquette contient déjà des données, Dossivoix demande une confirmation supplémentaire.
Choisissez **Remplacer** pour autoriser le remplacement, ou **Garder** pour conserver
l'étiquette. Vous pouvez aussi répondre « oui » ou « non » pendant l'écoute.
Après confirmation, présentez de nouveau la même étiquette, seule : l'app vérifie
son contenu, mais ne distingue pas deux étiquettes dont le contenu est identique.

## Comprendre les commandes

- **Voix** lance l'écoute adaptée à l'écran : « lire ou écrire » à l'accueil,
  reprise d'une dictée en pause, ou réponse à la confirmation affichée.
- **J'écoute** indique que le micro écoute. Un bref son accompagne le début et la fin
  de l'écoute normale ; son audibilité dépend du volume et de la sortie audio.
- **Annuler** coupe la parole et le micro, sans écrire ni effacer le texte dicté.
  Pendant la dictée, « annuler la dictée » permet aussi de mettre en pause.
- **Terminer** finit la dictée et demande confirmation ; il n'écrit pas directement.
- **Abandonner** quitte l'écriture et efface le brouillon.

Pendant une opération NFC, les boutons de parcours sont désactivés. La fenêtre NFC
d'iOS permet d'annuler cette opération. Si une écriture a été interrompue, relisez
l'étiquette pour vérifier son contenu.

## Si la dictée s'arrête trop tôt

Une écoute de dictée dure au maximum **55 secondes**. Elle se termine aussi après
**30 secondes sans nouvelle transcription**. Le service de reconnaissance d'Apple
peut s'arrêter plus tôt. L'arrêt automatique relit le texte et demande confirmation.
Si vous souhaitez compléter ce texte, dites **« continuer »** pendant la question.

Après un arrêt avec **Annuler**, un appel ou un passage en arrière-plan, touchez
**Voix** pour reprendre la dictée en pause. Le texte déjà transcrit est conservé
en mémoire ; les mots que le système n'a pas transcrits ne peuvent pas être récupérés.
Fermer complètement l'app fait perdre le brouillon. Vérifiez toujours la relecture.

Les expressions « terminer la dictée » et « annuler la dictée », en fin de phrase,
sont interprétées comme des commandes. Si votre étiquette doit contenir ces mots,
commencez la dictée par **« texte littéral »**, puis dictez le contenu et utilisez
le bouton **Terminer**. Les deux mots d'introduction ne sont pas écrits.

## Utiliser Siri

Essayez **« Lis l'étiquette avec Dossivoix »** ou
**« Écris une étiquette avec Dossivoix »**. Aucun raccourci n'est à créer.
Si Siri comprend mal le nom, essayez « Dossi voix », ou ouvrez l'app et utilisez
**Lire**, **Écrire** ou **Voix**.

## Questions fréquentes

**Puis-je utiliser l'app sans autoriser le micro ?**

Oui pour lire : utilisez **Lire**. L'écriture demande le micro et la reconnaissance
vocale, car le texte est dicté. Les autorisations se modifient dans les Réglages d'iOS.

**L'étiquette n'est pas détectée.**

Approchez le haut de l'iPhone, près de l'appareil photo, à un ou deux centimètres,
et gardez-le immobile. Une coque épaisse ou métallique peut gêner la détection.

**L'étiquette est verrouillée.**

Elle peut encore être lue, mais plus modifiée. Dossivoix ne verrouille pas les étiquettes.

**Le texte est trop long.**

La place disponible dépend de l'étiquette. Elle se mesure en octets, pas en nombre
fixe de caractères : les accents et les emojis peuvent occuper davantage de place.
Dossivoix vérifie la capacité et demande un texte plus court si nécessaire ;
elle ne tronque pas le texte pour le faire tenir.

**Quels contenus sont pris en charge ?**

Les étiquettes NFC NDEF texte (`text/plain` et RTD_TEXT). Les contenus audio
ne sont pas pris en charge.

**Le format de l'étiquette n'est pas reconnu.**

Ouvrez **À propos → Dépannage → Diagnostic**, puis **Partager ce rapport** pour
joindre les détails à une demande d'aide. Le rapport contient les données de
l'étiquette : utilisez une étiquette d'essai sans information confidentielle.
Rien n'est envoyé sans votre action.

## Nous contacter

Écrivez à [luca.mandrelli@icloud.com](mailto:luca.mandrelli@icloud.com),
ou [ouvrez un ticket sur GitHub](https://github.com/lmandrelli/dossivoix/issues).
Les tickets nécessitent un compte GitHub et sont publics : n'y publiez pas de données
personnelles ni le contenu confidentiel de vos dossiers.

L'aide et la confidentialité sont aussi accessibles dans l'app, via **À propos**.

[Accueil](index.html) · [Politique de confidentialité](privacy.html)
