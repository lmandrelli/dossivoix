# NFC vierge — essai local 1.1 (11)

Le build 10 a été refusé par les étiquettes de l'utilisateur (« non compatible »).
Son correctif a été annulé par `07f8fb8`, sur `codex/1.1-nfc-additive`, avant de
repartir du comportement NDEF du build 7. Les modifications locales de main
(builds 8/9) restent séparées et ne sont pas incluses.

## Nouvelle méthode

La détection physique reste nécessaire pour voir une puce sans message NDEF.
Les modes ISO 14443, ISO 15693 et FeliCa NDEF sont déclarés, avec l'AID Type 4.
Dès que CoreNFC annonce NDEF readWrite/readOnly, le parcours natif existant est
utilisé : readNDEF, WritePlanner, writeNDEF, relecture. Ni TagDecoder, ni
WritePlanner, ni SmartVisionFormat, ni leurs tests existants n'ont changé.

Uniquement si CoreNFC annonce notSupported :

- Lire le CC et les TLV Type 2, sans demander de version de puce si le CC est valide.
- Accepter les NULL et les TLV de contrôle d'usine, qui ne sont pas du texte utilisateur.
- En lecture, renvoyer le contenu NDEF ou le résultat vide, sans écrire.
- En écriture sur une structure vide, préparer un NDEF TNF Empty (`D0 00 00`)
  en conservant les contrôles TLV et les autres octets. Puis reconnecter et
  reprendre l'écriture native CoreNFC du texte, avec vérification native.
- Si le CC est entièrement nul, le préparer à partir du fabricant, type et taille
  GET_VERSION (NTAG213/215/216), sans filtrer l'antenne ni la révision. Le CC est
  écrit en dernier, jamais s'il est déjà non nul. Les verrous/configurations ne
  sont jamais écrits. Les protections matérielles restent appliquées par la puce.
- Chaque page préparée est relue ; la représentation de l'ACK ne décide plus du succès.
- Si CoreNFC conserve notSupported après reconnexion, redétecter une seule fois
  dans la même feuille NFC en imposant le même UID. Un nouvel échec est annoncé
  comme une écriture échouée ; aucune boucle de formatage.

La préparation peut être répétée après une interruption entre les commandes.
Les résidus identiques à la préparation attendue sont acceptés, mais aucune
donnée étrangère à celle-ci n'est écrasée. Les zones réservées décrites dans les
TLV sont protégées. Les contrôles stricts du build 10 sur l'intégralité du contenu,
la révision, les verrous globaux et la configuration ont été supprimés.

## Avis Claude Code

Deux consultations en lecture seule, demandées par l'utilisateur :

1. Analyse du parcours build 7 et recommandations : préparation minimale puis
   CoreNFC, reconnaissance des contrôles d'usine, GET_VERSION moins restrictif.
   Cette première analyse n'avait pas accès au diff retiré : les causes avancées
   restaient des hypothèses.
2. Relecture des fichiers exacts build 10 et de la nouvelle méthode : demande
   d'idempotence, de reprise après interruption et de redétection CoreNFC. Ces
   points ont été corrigés et testés. Les recommandations de rétrécir la lecture
   ou de modifier un CC partiellement écrit n'ont pas été retenues.

Les temps radio, le cache CoreNFC et l'encapsulation des erreurs matérielles
restent à vérifier sur iPhone. Le nombre de READ est volontairement conservateur :
seule la première page de chaque réponse est utilisée pour éviter les retours au
début de mémoire près d'une zone protégée.

## Validation

- 129 tests DossivoixCore, dont 14 nouveaux tests Type 2 : réussis.
- Tests applicatifs supplémentaires : transport simulé, CC écrit en dernier,
  absence d'écriture en lecture, absence de GET_VERSION avec CC valide,
  préparation répétable, vérification des pages, annulation et protections.
- Une étiquette déjà écrite n'est pas disponible chez l'utilisateur : aucune
  validation matérielle des anciennes étiquettes n'est revendiquée.
- Diffusion demandée : installation directe sur l'iPhone 16 Pro, sans TestFlight.

## Essai sur le téléphone

1. Vérifier « 1.1 (11) » dans À propos.
2. Lire la NTAG vierge : attendre « Étiquette vide ».
3. Sur cette étiquette, écrire un texte court dès la première approche en la
   maintenant immobile jusqu'à la confirmation.
4. Relire immédiatement le texte ; essayer un autre texte et vérifier la demande
   de remplacement avant réécriture.
5. Dès que possible, répéter avec une NTAG213 et une NTAG215 et lire les mêmes
   étiquettes sur SmartVision, puis relire une ancienne étiquette SmartVision.
6. En cas d'échec, relever l'étape et le message exact. Le résumé NTAG Reader
   initial ne contient pas les pages mémoire ; il ne prouve pas leur formatage.

Références : [Apple CoreNFC](https://developer.apple.com/documentation/corenfc/nfctagreadersession),
[NXP NTAG213/215/216](https://www.nxp.com/docs/en/data-sheet/NTAG213_215_216.pdf).

Résultat final le 13 novembre 2026 : 129 tests du package et 43 tests applicatifs
réussis ; build iOS signé 1.1 (11) compilé et installé avec succès via devicectl
sur l'iPhone 16 Pro de l'utilisateur. Aucun envoi App Store Connect/TestFlight.
La validation des échanges NFC réels est laissée à l'essai de l'utilisateur.
