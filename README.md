# Dossivoix

App iOS gratuite et open source (licence MIT) pour identifier ses dossiers papier à la voix,
grâce à des étiquettes NFC. On approche l'iPhone d'une étiquette : l'app annonce le nom du dossier.
Elle permet aussi d'écrire de nouvelles étiquettes, en dictant le nom.

Conçue pour une personne malvoyante qui utilisait un téléphone Kapsys SmartVision 2 :
les étiquettes existantes restent lisibles, et celles écrites par Dossivoix restent lisibles
par le SmartVision.

> 🚧 En cours de développement. Étapes : format NDEF ✅ · lecture · synthèse vocale · écriture ·
> dictée et réponses vocales · Siri · documentation de publication.

## Structure

| Dossier | Contenu |
|---|---|
| `Packages/DossivoixCore` | Logique pure, sans dépendance à iOS : format NDEF SmartVision, décodage tolérant, diagnostic, capacité. Testée avec XCTest. |
| `Dossivoix/` | Code de l'app (SwiftUI, services NFC et voix). |
| `Config/` | `Info.plist` (textes d'autorisation, `INAlternativeAppNames`) et entitlements NFC. |

## Format des étiquettes (SmartVision 2)

Puce NXP NTAG 213. Message NDEF de deux enregistrements MIME `text/plain`, sans identifiant :

```
92 0A 04 "text/plain" "TEXT"                        ← marqueur Kapsys
52 0A 18 "text/plain" "Dossier panneau solaire "    ← nom du dossier + espace final
```

Le marqueur et l'espace final sont réglables dans `SmartVisionFormat`.

## Tests

```bash
cd Packages/DossivoixCore && swift test
```

Si `xcode-select` pointe vers les Command Line Tools, préfixer par
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Licence

MIT, voir [LICENSE](LICENSE).
