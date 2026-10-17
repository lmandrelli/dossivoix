# Dossivoix – Étiquettes NFC vocales

App iOS gratuite et open source (licence MIT) pour identifier ses dossiers papier à la voix,
grâce à des étiquettes NFC. On approche l'iPhone d'une étiquette : l'app annonce le nom du
dossier. Elle écrit aussi de nouvelles étiquettes : on dicte le nom, on confirme, on approche
l'étiquette.

Conçue pour une personne malvoyante qui utilisait un téléphone **Kapsys SmartVision 2** :
les étiquettes existantes restent lisibles, et celles écrites par Dossivoix restent lisibles
par le SmartVision.

- Utilisation entièrement vocale (synthèse et reconnaissance en français), compatible VoiceOver.
- Lancement par **Siri classique**, sans Apple Intelligence ni configuration.
- Grands boutons à fort contraste en secours, saisie au clavier possible.
- Aucune donnée collectée, aucun serveur, aucune dépendance externe.

Pages publiques (GitHub Pages, dossier [`docs/`](docs/)) :
[assistance](https://lmandrelli.github.io/dossivoix/support) ·
[confidentialité](https://lmandrelli.github.io/dossivoix/privacy).

---

## Sommaire

1. [Utilisation](#utilisation)
2. [Architecture](#architecture)
3. [Format des étiquettes](#format-des-étiquettes)
4. [Mise en place dans Xcode](#mise-en-place-dans-xcode)
5. [Tests automatiques](#tests-automatiques)
6. [Réglages faciles à modifier](#réglages-faciles-à-modifier)
7. [Checklist de tests manuels sur iPhone](#checklist-de-tests-manuels-sur-iphone)
8. [Test croisé avec le SmartVision](#test-croisé-avec-le-smartvision)
9. [Publication sur l'App Store](#publication-sur-lapp-store)

---

## Utilisation

### Phrases Siri

| Lecture | Écriture |
|---|---|
| « Lis l'étiquette avec Dossivoix » | « Écris une étiquette avec Dossivoix » |
| « Dossivoix, lis l'étiquette » | « Dossivoix, écris une étiquette » |
| « Lire un dossier avec Dossivoix » | « Nouvelle étiquette avec Dossivoix » |
| « Ouvre Dossivoix en lecture » | « Ouvre Dossivoix en écriture » |

L'app s'ouvre et démarre aussitôt le parcours, sans toucher l'écran.

### Parcours vocal

**Lecture** : « Approchez l'étiquette » → nom du dossier (ou erreur en termes simples) →
« Dites *encore* pour lire une autre étiquette, ou *écrire* pour écrire une étiquette. »
Sans réponse, l'app s'arrête. Dire *écrire* à ce moment **renomme l'étiquette qui vient
d'être lue**.

**Écriture** : « Dites le nom du dossier » → « J'ai compris : … C'est bon ? »
(*oui* / *non* / *recommencer* / *annuler*) → vérification de la taille → « Approchez
l'étiquette » → écriture puis relecture de contrôle → « Étiquette écrite : … » →
« Dites *oui* pour écrire une autre étiquette. »

Si l'étiquette contient déjà autre chose : « Cette étiquette contient déjà : … Voulez-vous
la remplacer par : … ? ». Après un *oui*, il faut **approcher l'étiquette une deuxième
fois**. L'écriture n'a lieu que si son contenu n'a pas changé, ce qui évite d'écraser
une autre étiquette par erreur. **Une étiquette n'est jamais verrouillée.**

Après deux réponses incomprises, l'app renvoie vers l'écran (boutons ou clavier).

---

## Architecture

```
Packages/DossivoixCore/      Logique pure, sans iOS : testée avec `swift test`
  NDEF/                      Codec NDEF, format SmartVision, décodage tolérant, diagnostic, capacité
  NFC/                       TagError, WritePlanner (règles d'écriture), TagWriteOutcome
  Voice/                     Normalisation du texte, interprétation des réponses vocales
  Flow/VoiceFlow.swift       Machine à états du parcours vocal (FlowMachine)
  Speech/Phrases.swift       Toutes les phrases prononcées ou affichées
  Feedback/                  Signaux sonores (notes) et synthèse des sons
Dossivoix/                   App iOS (SwiftUI)
  Services/NFC/              CoreNFCTagService (lecture + écriture), protocoles TagReading/TagWriting
  Services/Speech/           Synthèse vocale, annonces VoiceOver, reconnaissance vocale
  Services/Audio/            Session audio .playAndRecord
  Services/Feedback/         Sons et vibrations
  Flow/                      FlowCoordinator (exécute les effets de la machine), journal de diagnostic
  Intents/                   App Intents, phrases Siri, LaunchRouter
  UI/                        Écran principal, écran Diagnostic
Config/                      Info.plist (textes d'autorisation, INAlternativeAppNames), entitlements
docs/                        Pages GitHub Pages (assistance, confidentialité)
```

**Machine à états** (`FlowMachine`) : chaque événement (bouton, résultat NFC, réponse
entendue) donne un nouvel état et une liste d'*effets* : parler, écouter, lire, écrire,
ouvrir le clavier. Le `FlowCoordinator` exécute ces effets dans l'ordre. La parole est
toujours terminée avant une écoute, et un nouvel événement coupe la parole et l'écoute
en cours.

```
idle ──Lire──▶ reading ──▶ offeringAfterRead ──« encore »──▶ reading
                                   └──« écrire »──▶ askingName (renommage)
idle ──Écrire─▶ askingName ──▶ confirmingName ──« oui »──▶ writing
                                                            ├─▶ offeringAnotherWrite
                                                            ├─▶ confirmingReplace ──« oui »──▶ writing (2e passage)
                                                            └─▶ offeringRetry ──« encore »──▶ writing
```

Les services (NFC, parole, écoute, sons, session audio) sont derrière des protocoles,
avec des versions simulées (`FakeTagService`, `ScriptedSpeechInput`, `SilentSpeechOutput`…).

---

## Format des étiquettes

Relevé avec NXP TagInfo sur une étiquette du SmartVision (puce NXP NTAG 213, 144 octets).
Message NDEF de 54 octets, deux *short records* MIME `text/plain`, sans identifiant :

```
92 0A 04 "text/plain" "TEXT"                        ← marqueur ajouté par l'appli Kapsys
52 0A 18 "text/plain" "Dossier panneau solaire "    ← nom du dossier + espace final
```

- **Écriture** : reproduction à l'identique. Le marqueur et l'espace final sont réglables
  (`SmartVisionFormat.writesMarker`, `.appendsTrailingSpace`).
- **Lecture** : tolérante. Le marqueur est ignoré, les espaces superflus sont supprimés, et
  les textes « Well-known » (RTD_TEXT, UTF-8 ou UTF-16) sont acceptés. Tout contenu inconnu
  est annoncé comme « Étiquette d'un format non reconnu » et détaillé dans l'écran
  **Diagnostic** (TNF, type, contenu en hexadécimal et en UTF-8), à partager.
- **Capacité** : 141 octets de message sur une NTAG 213, soit 110 octets pour le nom.
  Une lettre accentuée compte pour 2 octets. La capacité réelle de l'étiquette est
  revérifiée au moment d'écrire.

> Les octets de référence des tests sont reconstitués à partir du relevé TagInfo.
> À remplacer par un vidage mémoire complet (TagInfo « Full scan ») dès que possible :
> `Packages/DossivoixCore/Tests/DossivoixCoreTests/Fixtures.swift`.

---

## Mise en place dans Xcode

### Prérequis

- Mac avec **Xcode 16 ou plus récent** (développé avec Xcode 27). Cible : iOS 17, iPhone uniquement.
- **Compte Apple Developer payant** (99 €/an). La capacité *NFC Tag Reading* n'est pas
  disponible avec une équipe personnelle gratuite. Elle est indispensable même pour
  installer l'app sur son propre iPhone.
- Un iPhone XS ou plus récent. Le NFC ne fonctionne pas dans le simulateur.

Si `xcodebuild` ou `swift test` utilisent les Command Line Tools au lieu de Xcode :

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Réglages

1. Ouvrir `Dossivoix.xcodeproj`. Le package local `DossivoixCore` est relié automatiquement.
2. Cible **Dossivoix → Signing & Capabilities** :
   - **Team** : choisir l'équipe du compte développeur ;
   - **Bundle Identifier** : `work.lmandrelli.dossivoix` (à garder : il ne change plus après publication) ;
   - vérifier la capacité **Near Field Communication Tag Reading**. Elle vient de
     `Config/Dossivoix.entitlements`, avec la valeur `TAG` : depuis le SDK iOS 17,
     App Store Connect refuse `NDEF` seul.
3. Aucune capacité *Siri* n'est nécessaire : les App Shortcuts (App Intents) n'en ont pas besoin.
4. Brancher l'iPhone et lancer (⌘R). Le premier lancement sur un appareil demande d'approuver le
   profil développeur dans **Réglages → Général → VPN et gestion de l'appareil**.

### Essayer sans étiquette ni micro (Debug uniquement)

Dans **Product → Scheme → Edit Scheme → Run → Arguments**, ajouter :

- `-FakeNFC` : étiquettes simulées (une étiquette SmartVision « Dossier panneau solaire »,
  puis un remplacement accepté) ;
- `-FakeVoice` : réponses vocales simulées (« banque », « oui », « oui », puis silence).

Ces options n'existent pas dans les versions de publication.

---

## Tests automatiques

```bash
cd Packages/DossivoixCore && swift test
```

Ou **⌘U** dans Xcode (schéma *Dossivoix*). Les 94 tests couvrent :

- le codec NDEF et le format SmartVision, à partir des octets réels ;
- le décodage tolérant et le diagnostic ;
- la capacité des étiquettes et les règles d'écriture (remplacement, 2ᵉ passage, verrouillage) ;
- l'interprétation des réponses vocales ;
- la machine à états, parcours complets compris.

---

## Réglages faciles à modifier

| Quoi | Où |
|---|---|
| Nom de l'app (affiché, prononcé, utilisé par Siri) | Réglage de build `APP_DISPLAY_NAME` de la cible |
| Variantes de prononciation pour Siri | `Config/Info.plist` → `INAlternativeAppNames` (vide au départ, exemple en commentaire) |
| Phrases Siri | `Dossivoix/Intents/DossivoixShortcuts.swift` |
| Toutes les phrases prononcées | `Packages/DossivoixCore/Sources/DossivoixCore/Speech/Phrases.swift` |
| Mots compris (oui, non, recommencer…) | `VoiceAnswerParser.vocabulary` |
| Marqueur « TEXT » et espace final | `SmartVisionFormat` |
| Délais d'écoute (début, silence, durée max) | `ListenKind.timing` |
| Nombre d'essais avant renvoi vers l'écran | `FlowMachine.maxAttempts` |
| Cohabitation avec VoiceOver | `VoiceSettings` (`AdaptiveSpeechOutput.swift`) |
| Sons « j'écoute », succès, erreur | `FeedbackCue.notes` |

**VoiceOver** : par défaut, l'app parle elle-même avec la voix et le débit de VoiceOver.
La fin de chaque phrase est alors connue avec certitude, ce qui permet d'enchaîner
parole puis écoute. La consigne « Approchez l'étiquette » est omise, car VoiceOver lit déjà
la feuille NFC. Si des conflits apparaissent, passer
`VoiceSettings.usesVoiceOverAnnouncements` à `true` pour confier les phrases à VoiceOver.

---

## Checklist de tests manuels sur iPhone

Préparer : 2 étiquettes NTAG 213 vierges, 2 étiquettes écrites par le SmartVision, une
étiquette « sacrifiée » verrouillée (avec une app tierce, de façon irréversible, **sur une
étiquette dédiée uniquement**), des écouteurs Bluetooth, de la musique en lecture.

### Premier lancement
- [ ] Les trois demandes d'autorisation (NFC, micro, reconnaissance vocale) s'affichent en
      français, au bon moment (micro et reconnaissance : à la première écoute).
- [ ] Refuser micro ou reconnaissance : l'app annonce que la reconnaissance vocale n'est pas
      disponible et ouvre la saisie au clavier ; la lecture reste possible.

### Lecture (sans VoiceOver)
- [ ] Étiquette SmartVision : le nom est annoncé, sans le marqueur ni l'espace final.
- [ ] Étiquette vierge : « Étiquette vide ».
- [ ] Étiquette d'un autre format (URL, vCard…) : « format non reconnu », visible dans Diagnostic, partage OK.
- [ ] Retirer l'étiquette trop vite : message « retirée trop tôt ».
- [ ] Toucher *Annuler* sur la feuille NFC : « Lecture annulée », pas de son d'erreur.
- [ ] Attendre 60 s sans étiquette : « Aucune étiquette détectée », puis proposition encore / écrire.
- [ ] Dire « encore » : nouvelle lecture. Ne rien dire : l'app s'arrête, le nom reste affiché.
- [ ] Dire « écrire » après une lecture : « Dites le nouveau nom pour : … », renommage sans
      question de remplacement ; avec une autre étiquette, refus « Ce n'est pas la même étiquette ».

### Écriture (sans VoiceOver)
- [ ] Dictée d'un nom, fin détectée après un court silence ; majuscule initiale appliquée.
- [ ] Réponses : oui, d'accord, c'est ça / non, recommencer, refaire / annuler, stop.
- [ ] Réponse incompréhensible deux fois : renvoi vers l'écran avec le nom pré-rempli.
- [ ] Nom très long (> 110 caractères) : demande d'un nom plus court, avant d'approcher l'étiquette.
- [ ] Étiquette vierge : écrite directement, « Étiquette écrite : … », puis relecture correcte.
- [ ] Étiquette déjà écrite : question « Remplacer ? » ; « non » la laisse intacte ; « oui » puis
      2ᵉ passage avec la **même** étiquette : remplacée ; avec une **autre** : refus, rien d'écrit.
- [ ] Étiquette verrouillée : « Cette étiquette est verrouillée ».
- [ ] Vérifier qu'aucune étiquette écrite par l'app n'est verrouillée (TagInfo).
- [ ] Saisie au clavier : écriture sans confirmation orale.

### Audio
- [ ] Jamais de parole pendant l'écoute ; bip « j'écoute » avant chaque écoute.
- [ ] Sons et vibrations distincts pour succès et erreur.
- [ ] Musique en fond : elle baisse pendant la parole et reprend à la fin.
- [ ] Écouteurs Bluetooth : la voix passe dans les écouteurs.
- [ ] Mode silencieux activé : la voix reste audible.
- [ ] Appel entrant ou passage en arrière-plan pendant un parcours : l'app se tait, puis reste utilisable.

### Avec VoiceOver
- [ ] Les boutons sont annoncés clairement (« Lire une étiquette », « Écrire une étiquette »…).
- [ ] Pas de double voix : la feuille NFC lue par VoiceOver, puis le résultat par l'app.
- [ ] La voix de l'app reprend la voix et le débit réglés dans VoiceOver.
- [ ] VoiceOver ne parle pas pendant les écoutes (sinon, l'écoute capte VoiceOver).
- [ ] Parcours complets lecture et écriture uniquement à la voix.
- [ ] Taille de texte maximale (Réglages → Accessibilité → Affichage et taille du texte) : tout reste lisible.
- [ ] **Thème clair** : noir sur blanc. **Thème foncé** : blanc sur noir.
- [ ] **Inversion intelligente** (Réglages → Accessibilité → Affichage et taille du texte) en thème clair :
      fond noir et texte blanc, sans aucun bloc blanc. En thème foncé + inversion (rare), l'app repasse en
      noir sur blanc pour rester sombre une fois inversée.
- [ ] Rien ne bouge à l'écran, sauf le panneau « J'écoute » ; avec « Réduire les animations », il apparaît
      en fondu et ses barres restent immobiles.

### Siri
- [ ] Juste après l'installation, sans ouvrir l'app : « Lis l'étiquette avec Dossivoix ».
- [ ] iPhone **déverrouillé** : chaque phrase (8) ouvre l'app et démarre le bon parcours sans toucher l'écran.
- [ ] iPhone **verrouillé** : Siri demande Face ID / code, puis le parcours démarre.
- [ ] Avec VoiceOver actif, depuis l'écran verrouillé.
- [ ] « Dis Siri » mains libres et bouton latéral.
- [ ] Si Siri comprend mal « Dossivoix » : noter ce qu'il comprend et l'ajouter dans `INAlternativeAppNames`.
- [ ] Les raccourcis apparaissent dans l'app Raccourcis et dans la recherche.

---

## Test croisé avec le SmartVision

But : vérifier que les étiquettes passent d'un appareil à l'autre dans les deux sens.

1. **SmartVision → iPhone** : lire avec Dossivoix 3 étiquettes écrites par le SmartVision,
   dont une avec accents (« Impôts 2024 ») et une longue. Les noms doivent être annoncés correctement.
2. **iPhone → SmartVision** : écrire avec Dossivoix 3 étiquettes vierges (même noms), puis
   les lire avec le SmartVision.
3. **Comparer les octets** : dans Dossivoix, écran **Diagnostic**, partager le rapport d'une
   étiquette écrite par le SmartVision et celui d'une étiquette écrite par Dossivoix avec le
   même nom. Les lignes « Octets » doivent être identiques. Faire de même avec NXP TagInfo.
4. **Si le SmartVision ne lit pas** les étiquettes de Dossivoix, essayer dans l'ordre :
   - sans l'espace final (`appendsTrailingSpace = false`) ;
   - sans le marqueur (`writesMarker = false`) ;
   - sinon, comparer le vidage mémoire complet avec TagInfo : CoreNFC décide lui-même de
     l'encodage des octets. En dernier recours, il faudrait écrire les pages brutes de la
     NTAG (`NFCMiFareTag`, valeur `TAG` déjà présente dans les entitlements).
5. Remplacer les octets de `Fixtures.swift` par le vidage réel et relancer `swift test`.

---

## Publication sur l'App Store

Nom prévu : **Dossivoix – Étiquettes NFC vocales**. App gratuite, développeur particulier
(statut **non-commerçant** à déclarer dans App Store Connect pour l'UE, au titre du DSA).

- [x] **Icône** Liquid Glass : `Dossivoix/AppIcon.icon` (dossier jaune et bulle de parole avec
      une onde sonore, sur fond graphite #1C1C1E en mode clair comme sombre),
      modifiable dans **Icon Composer** (Xcode → Open Developer Tool). Calques SVG dans
      `AppIcon.icon/Assets/`. Xcode génère seul les versions plates pour iOS 17 à 25.
- [ ] Captures d'écran iPhone (6,9" et 6,5"), en français.
- [ ] Activer **GitHub Pages** : Settings → Pages → *Deploy from a branch* → `main` / `docs`.
      URLs : `https://lmandrelli.github.io/dossivoix/privacy` et `/support`.
- [ ] App Store Connect → *Confidentialité de l'app* : **Aucune donnée collectée**.
- [ ] Catégorie : Utilitaires (ou Productivité) ; classification d'âge 4+.
- [ ] Export / chiffrement : déjà déclaré (`ITSAppUsesNonExemptEncryption = NO`).
- [ ] Notes pour la revue : contenu de [`APP_REVIEW_NOTES.md`](APP_REVIEW_NOTES.md), avec
      une vidéo de démonstration sur iPhone avec une vraie étiquette.
- [ ] Archive : **Product → Archive**, puis *Distribute App → App Store Connect*.

Points de conformité déjà en place :
- aucune API privée, aucune dépendance ;
- manifeste de confidentialité `PrivacyInfo.xcprivacy` (rien de collecté, aucune API
  « à justification ») ;
- textes d'autorisation explicites en français ;
- fonctionnement clair sans étiquette : chaque situation a un message.

---

## Licence

MIT, voir [LICENSE](LICENSE). Politique de confidentialité : [docs/privacy.md](docs/privacy.md).
