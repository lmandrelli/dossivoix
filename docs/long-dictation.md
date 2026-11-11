# Dictée et commandes simplifiées

État après les essais utilisateur du 11 novembre 2026. Branche isolée alignée sur
`origin/main` (`30fadaa`) par `9e98813`. Le checkout principal reste inchangé ; aucun
push, archive ou envoi App Store n'a été effectué depuis cette branche.

## Parcours courant

- **Lire** effectue une lecture, annonce son contenu, puis revient au repos. Aucune
  proposition de relecture et aucune écoute automatique après la lecture.
- **Écrire** demande le nom avec une consigne courte. Dire « terminer la dictée » ou
  toucher **Terminer** pour finir. L'arrêt automatique relit également directement
  **« J'ai compris : … C'est bon ? »**. Il n'écrit jamais sans confirmation.
- Après écriture réussie ou erreur NFC, retour au repos : pas de proposition d'enchaîner.
- **Voix** au repos propose « Dites lire ou écrire ». Pendant une confirmation, il
  répète la question et réactive l'écoute. Pendant une dictée suspendue, il reprend
  avec le texte conservé. Il est désactivé pendant une opération NFC.
- **Arrêter** (même emplacement que Voix, tant que l'app parle ou écoute) coupe
  seulement la parole et le micro : rien n'est validé, rien n'est effacé. Dire
  « annuler » ou « annuler la dictée » a le même effet. Seuls **Abandonner** (dictée)
  et **Garder** (remplacement) quittent l'écriture. Le clavier n'est plus proposé.

La consigne avancée « texte littéral » n'est plus annoncée. Les commandes de dictée
restent réservées en suffixe ; la relecture permet de vérifier le résultat avant toute
écriture. Dire « encore » ou « continuer » pendant la confirmation permet toujours
l'ajout d'un segment si une session système s'est interrompue trop tôt, sans présenter
une question supplémentaire à chaque arrêt.

## Trois emplacements, un sens par action

Revue du 11 novembre (retour : « J'écoute devrait être grisé », boutons aux effets
proches, « Annuler devrait juste arrêter le mode vocal »). Anomalies corrigées :

- Voix restait actif pendant l'écoute et la relançait ; Arrêter et Annuler faisaient la
  même chose et effaçaient le brouillon ; « annuler » dit pendant la dictée le perdait.
- Terminer en pause sans texte relançait la dictée comme Voix ; un premier silence
  annonçait « Appuyez sur Voix » alors que le micro se rouvrait seul.
- États sans issue d'écran (relance après écriture, nouvel essai) et chemins clavier
  devenus inaccessibles : supprimés de la machine ; un brouillon pouvait survivre au repos.

La matrice est calculée par `FlowMachine.controls(voice:)` (`ScreenControls.swift`),
et l'écran l'affiche sans logique propre. Un appui sur un bouton qui n'est plus proposé
est ignoré.

| Contexte | Grand bouton 1 | Grand bouton 2 | Voix |
|---|---|---|---|
| Repos, résultat lu, menu vocal | Lire | Écrire | Voix / Arrêter |
| Session NFC (lecture, écriture) | Lire inactif | Écrire inactif | Voix inactif |
| Consigne parlée, dictée | Terminer (actif dès l'écoute) | Abandonner | Arrêter |
| Dictée en pause (arrêt, appel, arrière-plan) | Terminer (si texte) | Abandonner | Voix |
| Confirmation du nom | C'est bon (inactif si trop long) | Recommencer | Voix / Arrêter |
| Remplacement | Remplacer | Garder | Voix / Arrêter |

Effets : Terminer relit le texte et demande « C'est bon ? » ; seuls C'est bon et
Remplacer (ou « oui ») écrivent. Arrêter met la dictée en pause avec son texte, laisse
une question affichée avec ses boutons, referme le menu vocal. Une interruption audio ou
le passage en arrière-plan appliquent les mêmes règles ; une session NFC interrompue
reste signalée (« Relisez l'étiquette »).

## Repères visuels

Les deux grands boutons et le bouton Voix (80 points) occupent des emplacements fixes en
bas. Pendant que l'app parle ou écoute, le bouton Voix montre à gauche l'état grisé
(**J'écoute** avec ondes, ou **Je parle**), qui informe sans inviter à toucher, et à
droite **Arrêter** à contour plein ; tout le cadre arrête la voix. VoiceOver lit
« Arrêter la voix, J'écoute ». Un bouton inactif est atténué et à contour en tirets :
l'état ne dépend pas de la seule couleur. Le gris est un voile d'encre sur fond noir ou
blanc pur, sans aplat blanc après inversion intelligente. Le message occupe
l'espace restant et sa taille diminue selon la place disponible : il ne pousse pas
les boutons. Les libellés des boutons s’ajustent aussi, sans changer leurs cadres. Les icônes
restent présentes même en taille d’accessibilité maximale.
En paysage large, les deux actions sont côte à côte. Les régions réservées à la
charnière Duo sont toujours respectées. Le compromis est une réduction de la taille
visuelle des messages longs, y compris avec Dynamic Type ; VoiceOver conserve le
texte complet. L'essai par l'utilisateur malvoyant reste nécessaire.

## Limites et conservation

Une session dure au maximum 55 secondes, autorisations exclues. Elle s'arrête aussi
après 30 secondes sans nouvelle transcription. Ce délai utilise les résultats Speech,
pas une mesure acoustique du silence. Apple peut terminer une session avant ces délais.
La commande de fin partielle attend 1,5 seconde de stabilité ; un résultat final réussi
peut la déclencher immédiatement. Une correction de transcription annule cette attente.

L'app conserve la transcription déjà reçue, jamais l'audio. Une erreur, un appel ou le
passage en arrière-plan ne permet pas de récupérer les mots non transcrits. Après une
interruption audio/arrière-plan, le micro ne reprend pas seul : utiliser Voix. Le
brouillon est en mémoire et ne survit pas à une fermeture forcée. Les générations de
sessions protègent les nouveaux parcours des callbacks, autorisations et timers périmés.

[SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
documente des limites de durée et de disponibilité. La reconnaissance sur l'appareil
est demandée seulement quand elle est prise en charge ; sinon Internet et un traitement
chez Apple peuvent être nécessaires. Pas de promesse de dictée infinie ou locale universelle.

Le contrôle de capacité reste calculé en octets UTF-8, avec le format NDEF. Aucun texte
n'est tronqué pour tenir sur l'étiquette. L'annonce de dépassement est simple et demande
un texte plus court. Les confirmations de remplacement, y compris de contenu non reconnu,
la vérification de la seconde passe et les avertissements d'écriture interrompue restent
conservés. Les anciennes API internes de saisie restent couvertes pour ne pas affaiblir
ces protections, mais aucune saisie clavier n'est accessible depuis l'écran principal.

## Validation

- Suite Xcode iPhone 17 simulé / iOS 27.2 : 111 tests Core et 20 tests iOS réussis.
  Log : `/tmp/dossivoix-simple-ios-final.log`.
- Après simplification de la phrase de dépassement : 111 tests Core réussis,
  `/tmp/dossivoix-simple-core-final.log` ; compilation iOS signée réussie,
  `/tmp/dossivoix-simple-device-final.log`.
- Installation Debug réussie sur l'iPhone 16 Pro de Luca pour essai direct.
- Vérifications sur simulateur : boutons ancrés, lecture simulée sans relance,
  absence de clavier, texte agrandi. Aucun nouvel essai NFC physique n'est revendiqué.

Les tests couvrent notamment les pauses de 16 secondes, délais d'inactivité simulés,
fin système, transcription partielle, erreurs, annulation, reprise sans concaténer les
réponses de confirmation, relance vocale contextuelle et confirmations NFC.

Le retour utilisateur déjà consigné dans le README reste
valable pour ses essais antérieurs de lecture/écriture, sans inventer leur build exact.
Il ne vaut pas validation de cette nouvelle interface. Restent à essayer sur téléphone :
lecture/écriture réelle avec l'étiquette disponible, dictée hésitante, arrêt automatique,
reprise, VoiceOver, refus de permissions, appels, Bluetooth et texte long.

## Correction de la perte du début après une pause (11 novembre)

Le retour physique de Luca (« elle oublie le début ») révèle un cas absent des tests
précédents : un callback Speech peut ne contenir que le nouvel énoncé, sans mettre
`isFinal` à vrai. Remplacer le brouillon par chaque `formattedString` perdait alors
les phrases précédentes. Les changements de mise en page n'avaient pas rétabli
l'ancien délai court ; la conservation était incomplète depuis la première version.

`DictationTranscript` conserve les énoncés en utilisant leurs positions dans l'audio
et les métadonnées de fin d'énoncé. Les hypothèses partielles restent remplaçables ;
les résultats cumulatifs et les rappels identiques ne sont pas ajoutés plusieurs fois.
Une même phrase prononcée à deux moments distincts reste conservée deux fois.
L'accumulateur est propre à l'écoute et protégé par sa génération. Le parseur de fin
reçoit le texte assemblé, y compris quand la commande arrive dans un énoncé séparé.

Références : [positions des segments Speech](https://developer.apple.com/documentation/speech/sftranscriptionsegment/timestamp)
et [signalements de développeurs sur le forum Apple](https://developer.apple.com/forums/thread/762952).
Ces signalements ne constituent pas une garantie de comportement sur tous les iOS.
Sans positions exploitables ni métadonnées de fin d'énoncé, une hypothèse reste
traitée comme une révision : on ne peut pas distinguer sûrement une correction
complète d'un nouvel énoncé avec le seul texte. Aucun contenu dicté ni audio n'est
ajouté aux logs. Le nouvel essai réel sur l'iPhone reste indispensable.

Scénario physique à refaire : dicter une première phrase, attendre 3 à 5 secondes,
dicter une deuxième, attendre de nouveau, puis dire « terminer la dictée ». Vérifier
que la relecture contient les deux phrases avant de confirmer. Refaire avec Terminer,
avec une phrase volontairement répétée et avec un texte proche de la capacité NFC.

Validation du correctif : 111 tests Core et 28 tests iOS réussis (139 au total),
avec révisions partielles, énoncés séparés, répétitions horodatées, résultats cumulatifs,
fin vocale séparée, arrêt tactile, erreur et callbacks périmés. Log :
`/tmp/dossivoix-transcript-tests.log`. Compilation Debug signée pour l'iPhone réussie :
`/tmp/dossivoix-transcript-device.log`. Ces résultats automatisés ne remplacent pas
la reproduction avec le moteur Speech réel et les pauses de Luca.

## Validation de la matrice à trois emplacements (11 novembre)

115 tests Core et 32 tests iOS réussis (147 au total) sur iPhone 17 simulé / iOS 27.2,
log `/tmp/dossivoix-controls-fix-test.log`. Nouveaux tests : matrice par contexte,
exploration des états atteignables (issue toujours disponible, aucun bouton actif sans
effet, aucun brouillon caché au repos, écriture uniquement après C'est bon / Remplacer),
arrêt pendant dictée, confirmation et résultat parlé, résultat d'écoute tardif après
l'arrêt, appuis tardifs ignorés, Voix inactif pendant le NFC. Compilation Debug signée pour
l'iPhone réussie : `/tmp/dossivoix-controls-device-build.log`.

Non vérifié : rendu sur simulateur (appareils occupés par d'autres sessions), AX5, Duo,
inversion intelligente, VoiceOver réel. VoiceOver peut relire la valeur « J'écoute » du
bouton s'il a le focus quand l'écoute commence : à contrôler sur l'iPhone.

### Relecture et validation complémentaire du parent

Après les commits de Claude : correction de la conservation à l'écran du message
« Relisez l'étiquette » lorsque l'utilisateur coupe l'annonce d'une annulation NFC
renvoyée par le service (et pas seulement une interruption de l'app). Un test de
coordinateur couvre ce cas. Suite complète : 115 Core + 33 iOS = 148 tests réussis,
`/tmp/dossivoix-controls-parent-test.log`. Compilation signée réussie,
`/tmp/dossivoix-controls-parent-build.log`, puis installation sur l'iPhone 16 Pro.

Le parent a pu reprendre ses propres sessions simulateur : contrôle visuel iPhone
17e / AX5 / sombre, repos, dictée active et pause ; Duo / AX5 / clair dans la
configuration à deux régions déjà active. Icônes présentes, message ajusté, trois
commandes visibles. « Abandonner » a été ajusté sur une ligne pour éviter sa césure.
Recompilation simulateur et physique réussies après ce seul ajustement de présentation.
L'état J'écoute grisé et Arrêter ont été observés ensemble sur le 17e en AX5 sombre.
Ce contrôle ne couvre pas toutes les tailles ni tous les angles Duo. Inversion
intelligente, VoiceOver réel et NFC physique restent à vérifier sur téléphone.

### Ajustement demandé : indicateur libre et sons d'écoute

Le troisième emplacement est désormais une ligne stable : état « J'écoute » / « Je
parle » à gauche, sans fond gris ni contour ni action tactile, bouton **Voix** à
droite remplacé par **Annuler** pendant l'activité vocale. Annuler garde la même
sémantique que l'ancien Arrêter : coupe seulement la voix et conserve le brouillon.
Le bouton et l'état sont deux éléments d'accessibilité distincts ; changer l'état
n'altère plus la valeur VoiceOver du bouton. Les deux moitiés gardent leurs tailles.

Le signal montant existant (180 ms) est joué après les permissions, avant l'ouverture
du micro. Un signal descendant distinct (160 ms) suit la fermeture normale de l'écoute,
sa fin tactile, ou l'arrêt volontaire par Annuler. Il n'est pas joué pour arrêter une
simple annonce parlée, ni lors d'un appel ou passage en arrière-plan. Une nouvelle
action annule les signaux et continuations périmés. Un refus de permissions ne joue
pas le signal de départ. La session système peut encore échouer juste après le signal.
Les sons dépendent du volume et de la sortie audio de l'iPhone ; leur audibilité et
leur confort avec VoiceOver / Bluetooth restent à vérifier physiquement.

Validation : 152 tests réussis (115 Core, 37 iOS), log
`/tmp/dossivoix-voice-indicator-tests.log` ; compilation signée réussie,
`/tmp/dossivoix-voice-indicator-device.log`. Contrôle visuel de l'écoute sur iPhone 17e
simulé en AX5 sombre : indicateur libre et bouton Annuler séparés, icônes et libellés
entiers. Sons à juger sur l'iPhone ; pas de nouvelle validation NFC physique ni de
l'inversion intelligente. Aucun push ni modification du checkout principal.
