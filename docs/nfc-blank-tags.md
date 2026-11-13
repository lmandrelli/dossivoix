# NTAG vierges — version 1.1 (10)

Branche `codex/1.1-blank-ntag`, basée sur `6cd67a9` (version 1.0 build 7,
dernier commit de `origin/main` au démarrage du correctif). Les modifications
locales des builds 8 et 9 ne sont pas incluses.

## Comportement

La session utilise désormais `NFCTagReaderSession` pour détecter la puce avant
la lecture du message NDEF. Les technologies ISO 14443, ISO 15693 et FeliCa NDEF
sont interrogées ; les identifiants NDEF Type 4 et FeliCa sont déclarés dans Info.plist.

Une étiquette NDEF sans message continue de renvoyer une liste vide : le parcours
vocal annonce qu'elle est vide. En écriture, elle est écrite au premier passage.
Une étiquette contenant des données conserve le parcours de confirmation existant.

Si CoreNFC déclare le format NDEF non pris en charge, le repli reconnaît uniquement
les versions NXP NTAG213, NTAG215 et NTAG216 décrites dans la documentation constructeur.
La totalité de la mémoire utilisateur est lue par FAST_READ pour éviter qu'une
zone protégée ne provoque le retour au début de mémoire de la commande READ.
Seuls les octets tous nuls, un TLV NDEF vide suivi de zéros, ou un terminateur seul
suivi de zéros sont considérés comme vides. Les contenus inconnus sont refusés.
La lecture ne modifie jamais la puce.

Pour écrire une NTAG non formatée et vide : contrôle du CC, des verrous statiques
et dynamiques, de la protection par mot de passe et du miroir UID/compteur ;
contrôle de la capacité incluant le TLV et son terminateur ; écriture des pages
utilisateur avec longueur nulle temporaire, publication de la première page en
dernier ; initialisation du CC uniquement s'il est entièrement nul ; relecture
exacte des pages écrites et du CC. Les pages de verrouillage et de configuration
ne sont jamais écrites. Une interruption ou une réponse inattendue est un échec.
Le format des enregistrements texte SmartVision reste identique.

Le résumé NTAG Reader fourni identifie une NTAG215, mais ne contient pas les pages
mémoire : il ne permet pas de confirmer si le problème vient du formatage NDEF
ou de la détection. Les essais physiques ci-dessous restent indispensables.

## Validation sur iPhone — à effectuer avec le build 10

Pour chaque type NTAG213 et NTAG215, utiliser deux étiquettes vierges distinctes :

- Lire la première : la feuille Apple doit réagir et l'app annoncer une étiquette vide.
- Vérifier avec un lecteur externe que cette lecture n'a modifié aucune page.
- Écrire la seconde directement, sans lecture préalable : un seul passage, sans demande de remplacement.
- Relire avec Dossivoix, puis avec le SmartVision.
- Relire une étiquette déjà écrite par le SmartVision ; proposer un autre texte et vérifier la confirmation de remplacement.
- Essayer un texte trop long, une étiquette verrouillée et une étiquette protégée.
- Retirer l'étiquette pendant l'écriture : aucun faux succès.
- Approcher deux étiquettes, puis une seule ; annuler puis recommencer une session.
- Vérifier les annonces avec VoiceOver et sans VoiceOver.

Consigner le modèle d'iPhone, iOS, le type d'étiquette et le résultat. Les tests
unitaires et le simulateur ne valident pas les échanges radio NFC.

## Références

- [Apple — NFCTagReaderSession](https://developer.apple.com/documentation/corenfc/nfctagreadersession)
- [NXP — NTAG213/215/216](https://www.nxp.com/docs/en/data-sheet/NTAG213_215_216.pdf), mémoire et commandes GET_VERSION, FAST_READ, WRITE.

## Vérifications réalisées le 13 novembre 2026

- `swift test --package-path Packages/DossivoixCore` : 121 tests réussis, dont 6 nouveaux tests NTAG.
- Compilation iOS et archive Release signée 1.1 (10) : réussies.
- `xcodebuild test` sur iPhone 17e, iOS 27.2 simulé : réussi (tests applicatifs et package).
- Info.plist, entitlement NFC `TAG` et version de l'archive vérifiés.
- Essais radio NFC / SmartVision : à réaliser sur matériel physique.

Archive locale ignorée par Git : `DerivedData/Release-1.1/Dossivoix-1.1-10.xcarchive`.
Consignes TestFlight et brouillon des nouveautés dans `AppStore/` (matériel de
publication local, exclu du dépôt conformément à sa configuration existante).
