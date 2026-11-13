# Fonction avancée « Vider une étiquette » — 1.1 (15)

L'utilisateur a confirmé avec le build 14 que sa NTAG215 sans NDEF actif est
maintenant annoncée vide. Quelques essais avaient renvoyé « illisible » ; la
cause radio exacte n'est pas prouvée. Le parcours précédent lisait toute la
mémoire par pages individuelles, ce qui prolongeait le maintien dans le champ.

## Lecture plus courte

L'inspection s'arrête dès que la structure est suffisamment connue. Pour le
cas testé (CC valide, aucune encapsulation NDEF), trois commandes READ suffisent :
CC et deux pages utilisateur, au lieu de la lecture des 124 pages utilisateur.
Un TLV actif est lu jusqu'à la fin de son message. Les préfixes insuffisants
continuent la lecture ; le transport n'invente pas les octets manquants.

## Outil avancé

Dans À propos, le lien « Vider une étiquette » est placé immédiatement sous
« Ouvrir le diagnostic ». Il n'est pas ajouté aux parcours principaux.

L'écran explique l'action et demande confirmation avant d'ouvrir la feuille NFC.
L'effacement s'applique à la prochaine étiquette approchée. Annuler, quitter
l'écran ou passer en arrière-plan arrête la session. Le résultat est affiché et
annoncé à voix haute. Les échecs sont conservés dans Diagnostic.

Pour les Type 2 (dont NTAG213/215), l'outil remet la longueur du TLV NDEF à zéro
et ajoute un terminateur. Les TLV de contrôle, l'UID, le CC existant, les verrous
et la configuration sont conservés. Un CC entièrement absent peut être initialisé
pour les NTAG reconnues. Les pages modifiées sont relues et l'absence de NDEF actif
est vérifiée. Pour les autres étiquettes NDEF réinscriptibles prises en charge par
CoreNFC, un enregistrement TNF Empty est écrit et relu via l'API native.

Il s'agit d'un effacement logique du contenu NDEF, pas d'un effacement sécurisé
de tous les octets ni d'une réinitialisation des paramètres fabricant. Aucune
commande de verrouillage ou de déverrouillage n'est envoyée. Une étiquette déjà
verrouillée est refusée.

## Vérifications

Tests métier conservés, tests de lecture partielle, conservation des contrôles,
absence de NDEF après effacement, conservation de l'identité et des paramètres,
annulation sans écriture et erreur de relecture empêchant un faux succès.

Pas d'envoi TestFlight. Le build est destiné à l'essai direct sur l'iPhone.

Résultats le 13 novembre 2026 : 135 tests de logique métier et 50 tests applicatifs
réussis. Build signé 1.1 (15) installé sur l'iPhone 16 Pro. L'accès visuel au
simulateur n'était pas disponible via l'outil de contrôle ; l'essai physique du
bouton et de l'effacement reste à effectuer par l'utilisateur. Aucun effacement
d'étiquette physique n'a été déclenché automatiquement.

## Simplification — build 1.1 (16)

À la demande de l'utilisateur, l'écran intermédiaire est supprimé. Le paragraphe
explicatif et le bouton sont intégrés directement sous « Ouvrir le diagnostic »
dans À propos. Deux appuis suffisent : « Vider une étiquette », puis « Effacer »
dans l'unique boîte de confirmation. La feuille NFC s'ouvre ensuite.

Aucune synthèse vocale de l'app dans ce parcours. Le résultat reste affiché ;
un succès joue uniquement le signal sonore/haptique habituel de confirmation.
L'annulation, l'arrêt en arrière-plan, les rapports de diagnostic et les règles
NFC sont conservés. Aucun envoi TestFlight.
