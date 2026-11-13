# NFC sans enregistrement actif — build local 1.1 (14)

## Comportement retenu

Une puce Type 2 avec CC valide n'est pas incompatible parce qu'elle n'a pas de
message NDEF actif. Elle est annoncée vide et peut être initialisée puis écrite
dès la première approche. Les octets bruts non encapsulés ne sont pas recherchés
ni reconstitués en anciens textes. Le résultat est aligné sur « No NDEF Records ».

Les chemins CoreNFC readWrite/readOnly restent ceux du build précédent. Pour le
repli notSupported :

- accepter les familles MIFARE Ultralight et unknown si le CC Type 2 est valide ;
- accepter toute capacité Type 2 adressable par READ sur un octet (jusqu'à 1008
  octets), sans filtre de modèle ni de révision lorsque le CC est présent ;
- si un TLV NDEF actif existe, conserver ses enregistrements et les règles de
  confirmation de WritePlanner ;
- si aucune encapsulation NDEF n'est présente, renvoyer une liste vide,
  indépendamment des octets d'usine, métadonnées ou résidus ;
- en écriture, créer seulement une structure NDEF vide puis confier le message
  utilisateur à CoreNFC ; relecture de contrôle, protections et limite réelle
  de capacité conservées ;
- ne jamais modifier les pages de verrouillage ou de configuration.

Un CC absent ne permet pas de deviner la capacité : le GET_VERSION des NTAG21x
reste utilisé dans ce seul cas. Les autres technologies prises en charge par
CoreNFC utilisent toujours le parcours natif sans filtre ajouté.

## Diagnostic et correction de l'interprétation

Les builds locaux 12 et 13 ont servi à relever le refus du build 11. La capture
NXP fournie par l'utilisateur indique « No NDEF Records ». Des octets bruts
ressemblant à un message ont été observés, mais cela ne constitue pas un message
NDEF actif. La tentative de récupération automatique a été retirée avant
l'installation du build 14. Aucune donnée personnelle du relevé n'est ajoutée
au dépôt ; le test de cette disposition utilise du texte synthétique.

Les échecs de lecture/écriture apparaissent désormais dans Diagnostic, avec le
statut CoreNFC, le CC, l'UID permettant d'identifier la puce et les pages lues.
Les rapports restent en mémoire, limités aux 20 derniers et partagés uniquement
à la demande. Les annulations volontaires ne produisent pas de faux échec.

## Tests

- Absence de NDEF avec mémoire nulle, données d'usine ou octets résiduels : vide.
- Écriture directe sans confirmation sur cette absence de NDEF.
- NDEF actif existant : lecture inchangée et confirmation avant remplacement.
- Charge NDEF active mais malformée : contenu non reconnu, pas faux vide.
- Capacités Type 2 au-delà des seules NTAG213/215/216.
- Diagnostics d'échec, annulation et limite du journal.
- Tests métier et applicatifs existants, ainsi que transport simulé de préparation.

Pas d'envoi TestFlight : installation et vérification sur l'iPhone de l'utilisateur.

Validation logicielle : 135 tests du package et 46 tests applicatifs réussis.
Build signé 1.1 (14) installé et lancé sur l'iPhone 16 Pro le 13 novembre 2026.
La confirmation du résultat NFC physique est demandée à l'utilisateur.
