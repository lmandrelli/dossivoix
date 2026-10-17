# Notes pour l'équipe de revue App Store

Texte à coller dans App Store Connect → *App Review Information → Notes*.
Il est en anglais, la langue de travail de l'équipe de revue. À relire avant la soumission ;
Joindre avant soumission une courte vidéo sur iPhone avec une vraie étiquette, montrant
lecture, écriture et remplacement. Vérifier aussi le statut DSA dans App Store Connect
selon l'activité réelle du développeur ; la gratuité seule ne suffit pas à le déterminer.

---

## App Review Notes — Dossivoix

**Context.** Dossivoix is a free, open-source (MIT) accessibility app published by an
individual developer. It was built for a visually impaired person who used to
identify her paper folders with NFC stickers and a dedicated Android phone for blind users
(Kapsys SmartVision 2). Holding the iPhone near a folder's NFC tag makes the app speak the
folder's name aloud. The app can also write new tags: the user dictates the folder name.
The whole app is in French and designed to be used by voice and with VoiceOver.

**No data collection.** No account, no server, no analytics, no ads, no tracking. Tag contents
are kept in memory only (Diagnostic screen, hidden unless "Mode diagnostic" is turned on in
Settings → Dossivoix). Speech recognition uses Apple's Speech framework, on device when
available; otherwise audio may be processed by Apple under Apple's privacy policy.
Dossivoix does not store audio recordings. A Diagnostic report leaves the device only if the user shares it through the standard
share sheet. Privacy manifest included (no data collected; UserDefaults declared with reason
CA92.1, only to read the app's own "Mode diagnostic" setting).
Privacy, support and developer contact links are available from **À propos** on the main screen.

**Permissions.**
- NFC (NFCNDEFReaderSession): read and write NDEF tags. Tags are never locked.
- Microphone + Speech Recognition: short listening periods right after a spoken question
  (folder name, or answers such as "oui" / "non"). Never continuous listening.

**Siri.** Two App Shortcuts (App Intents, `openAppWhenRun`) with French phrases, e.g.
« Lis l'étiquette avec Dossivoix » (read a tag) and « Écris une étiquette avec Dossivoix »
(write a tag). They work with classic Siri, with no setup. When opened by Siri, the app starts
the corresponding flow after a short delay while in the foreground. Initial system permission
prompts and device unlocking may require user interaction. Voice recognition can be declined;
the **Clavier** button provides manual entry.

### How to test without NFC tags

An NFC-capable iPhone and writable NDEF tags (for example NTAG 213/215/216 stickers) are
required to review actual reading, writing and replacement. Without tags, the reviewer can
test the interface, dictation, keyboard fallback, cancellation and timeout handling:

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
5. Privacy and support: open **À propos** from the main screen.

### Reading and writing with real tags

1. Tap **Clavier**, type « Factures », confirm, and present a blank writable NDEF tag.
2. Tap **Lire** and present that tag: the app announces « Factures ».
3. Write a different name to that tag: the app asks before replacing existing content.
   Say « oui » and present the chosen tag again. Say « non » to cancel instead.
4. Present a tag with different content during that second pass: the app refuses to write.

The replacement check compares NDEF content, not a hardware identifier. Distinct tags
with identical content cannot be distinguished. Tags are never locked by the app.

### Contact

Source code: https://github.com/lmandrelli/dossivoix
Support: https://lmandrelli.github.io/dossivoix/support
Privacy policy: https://lmandrelli.github.io/dossivoix/privacy
