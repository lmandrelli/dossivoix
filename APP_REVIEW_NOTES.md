# Notes pour l'équipe de revue App Store

Texte à coller dans App Store Connect → *App Review Information → Notes*.
Il est en anglais, la langue de travail de l'équipe de revue. À relire avant la soumission ;
penser à joindre une courte vidéo de démonstration sur iPhone avec une vraie étiquette.

---

## App Review Notes — Dossivoix

**Context.** Dossivoix is a free, open-source (MIT) accessibility app published by an
individual, non-trader developer. It was built for a visually impaired person who used to
identify her paper folders with NFC stickers and a dedicated Android phone for blind users
(Kapsys SmartVision 2). Holding the iPhone near a folder's NFC tag makes the app speak the
folder's name aloud. The app can also write new tags: the user dictates the folder name.
The whole app is in French and designed to be used by voice and with VoiceOver.

**No data collection.** No account, no server, no analytics, no ads, no tracking. Tag contents
are kept in memory only (Diagnostic screen). Speech recognition uses Apple's Speech framework,
on device when available. A Diagnostic report leaves the device only if the user shares it
through the standard share sheet. Privacy manifest included (no data collected, no
required-reason API used).

**Permissions.**
- NFC (NFCNDEFReaderSession): read and write NDEF tags. Tags are never locked.
- Microphone + Speech Recognition: short listening periods right after a spoken question
  (folder name, or answers such as "oui" / "non"). Never continuous listening.

**Siri.** Two App Shortcuts (App Intents, `openAppWhenRun`) with French phrases, e.g.
« Lis l'étiquette avec Dossivoix » (read a tag) and « Écris une étiquette avec Dossivoix »
(write a tag). They work with classic Siri, with no setup. When opened by Siri, the app starts
the corresponding flow immediately, so that a blind user never needs to touch the screen.

### How to test without NFC tags

The app is fully usable without tags, and every situation produces a clear spoken and
on-screen message:

1. Launch the app (device language French recommended). The screen shows two large buttons:
   **Lire** (read) and **Écrire** (write).
2. Tap **Lire**: the system NFC sheet opens and the app says « Approchez l'étiquette »
   ("Hold the tag near the phone"). Without a tag, tap *Annuler* on the sheet: the app says
   « Lecture annulée » ("Reading canceled"). If you wait about 60 s, iOS ends the session and
   the app says « Aucune étiquette détectée » ("No tag detected").
3. Tap **Écrire**: the app asks « Dites le nom du dossier » ("Say the folder name").
   Say for example « Factures » ; it answers « J'ai compris : Factures. C'est bon ? »
   ("I understood: Factures. Is that right?"). Say « oui » ("yes"), then the NFC sheet opens
   to write the tag. Large on-screen buttons (*C'est bon*, *Recommencer*, *Saisir le nom au
   clavier*) offer the same choices without voice.
4. Siri: say « Lis l'étiquette avec Dossivoix » — the app opens and starts reading at once.

Any NFC Forum Type 2 tag (e.g. NXP NTAG 213/215/216 sticker) can be used to test reading
and writing. A demo video recorded on an iPhone with real tags is attached.

### Contact

Source code: https://github.com/lmandrelli/dossivoix
Support: https://lmandrelli.github.io/dossivoix/support
Privacy policy: https://lmandrelli.github.io/dossivoix/privacy
