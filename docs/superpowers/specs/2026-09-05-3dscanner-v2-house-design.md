# 3D Scanner v2 — Maison entière (brouillon à valider)

**Statut** : proposition rédigée le 2026-09-05 à l'issue de la v1, **non validée par Vincent**. À relire après la première utilisation réelle de la v1 sur iPhone : les retours terrain (précision, ergonomie du scan, formats réellement utilisés) peuvent changer les priorités ci-dessous.

Complète la spécification v1 (`2026-09-05-3dscanner-design.md`) ; les décisions D1–D23 restent en vigueur. Les identifiants continuent la numérotation : décisions **D24+**, fonctionnalités **F30+**.

## 1. Objectif

Scanner **toutes les pièces d'un logement**, les assembler en une maison cohérente (plusieurs pièces, plusieurs niveaux), la visualiser en 3D / 2D / AR et l'exporter dans les mêmes formats que la v1 — sans rien casser des scans v1 existants.

Ce que la v1 a déjà préparé (D14) : `House` / `Story` / `FloorPlan.transform`, tous les renderers, le scene builder et les exporteurs itèrent sur `house.allRooms`. La v2 ajoute la **capture** multi-pièces, la **fusion**, le **stockage** de la maison et l'**interface** de sélection ; l'aval ne change presque pas.

## 2. Ce qu'Apple fournit (vérifié dans RoomPlan, SDK iOS 27)

- `RoomCaptureSession.stop(pauseARSession: false)` : la session AR est conservée entre deux scans, donc les pièces successives partagent le **même repère monde**. `ScanCoordinator` possède déjà l'`ARSession` (v1), c'est la clé de tout.
- `StructureBuilder.capturedStructure(from: [CapturedRoom]) async throws -> CapturedStructure` : fusion Apple des pièces (murs mitoyens dédoublonnés, ouvertures partagées, sections nommées). `CapturedStructure` expose `rooms`, `walls`, `doors`, `windows`, `openings`, `floors`, `objects`, `sections`, `identifier`, `version` ; il est `Codable` et s'exporte en USDZ comme une pièce.
- Limites connues à mesurer sur le terrain : dérive de suivi sur un grand logement, escaliers (RoomPlan ne les modélise pas), extérieur / balcons ignorés.

## 3. Fonctionnalités v2

| ID | Fonctionnalité | Notes |
|---|---|---|
| F30 | Mode « Scanner la maison » : enchaîner les pièces sans quitter l'écran de capture (bouton « Pièce suivante »), session AR conservée | iPhone |
| F31 | Fusion automatique en fin de parcours (`StructureBuilder`), aperçu 2D de la maison avant enregistrement, possibilité d'exclure / rescanner une pièce | iPhone |
| F32 | Niveaux : détection par la hauteur du sol de chaque pièce (`floors` de la structure), regroupement en `Story`, nommage « Rez-de-chaussée », « Étage 1 »… éditable | Domain |
| F33 | Bibliothèque : une **maison** est un élément de premier niveau contenant ses pièces ; une pièce v1 isolée reste ouvrable telle quelle | iPhone + Mac |
| F34 | Visualiseur maison : pièces colorées par section, sélection d'une pièce (isolation / transparence des autres), sélecteur de niveau, AR 1:100 de la maison entière sur une table | iPhone + Mac |
| F35 | Plan 2D par niveau (une page PDF par étage), cotes des murs extérieurs et intérieurs, surfaces par pièce et totale | Export |
| F36 | Exports 3D de la maison (USDZ paramétrique de la structure, OBJ/STL/PLY avec un groupe par pièce), JSON, ZIP | Export |
| F37 | Fusion **manuelle** de pièces v1 scannées séparément (positionnement 2D à la main sur le plan, alignement de murs) — repli quand la session AR n'a pas pu être conservée | iPhone + Mac |
| F38 | glTF / GLB (écrivain maison : Model I/O ne l'écrit pas) ; boussole / nord ; unités impériales | v2.x |
| F39 | Relocalisation AR 1:1 dans la vraie maison via `ARWorldMap` sauvegardé au scan | v2.x |
| F40 | iPad (visualiseur + exports ; scan si LiDAR) | v2.x |

## 4. Décisions proposées

- **D24** Le fichier Apple `CapturedStructure` (JSON) devient la **source de vérité** d'une maison, comme `room.json` pour une pièce ; on conserve **aussi** chaque `room.json` d'origine pour pouvoir refusionner avec une version ultérieure de RoomPlan.
- **D25** Paquet `Documents/Houses/<uuid>.housescan/` : `structure.json` (Apple), `house.json` (`House` v1 sérialisée, lue par le Mac), `rooms/<uuid>.roomscan/` (paquets v1 inchangés), `house.usdz`, `thumbnail.png`, `meta.json`. Un `.housescan` se synchronise par iCloud comme un `.roomscan` (paquet = un seul document ubiquitaire).
- **D26** Le Domain reçoit un `ScanInput` **par pièce** plus une `StructureInput` neutre (murs fusionnés, sections, sols) ; `HouseBuilder` produit une `House` dont chaque `FloorPlan.transform` place la pièce dans le repère maison. Toujours zéro import de RoomPlan dans le Domain.
- **D27** Les niveaux sont déduits de la hauteur du sol (regroupement à ± 0,5 m) puis **éditables** ; jamais devinés à partir des noms.
- **D28** Les exports 2D produisent **une page par niveau** (PDF multipage, SVG et DXF avec un calque par niveau : `L0_WALLS`, `L1_WALLS`…) ; le titre-bloc indique le niveau et la surface du niveau.
- **D29** Compatibilité : les paquets `.roomscan` v1 restent lisibles et exportables sans migration ; `FloorPlan.schemaVersion` passe à 2 seulement si un champ change (aucun prévu).

## 5. Architecture (deltas)

```
Scan/        ScanCoordinator (+ mode maison : liste de CapturedRoom, session AR conservée)
             HouseScanFlow (UI : pièce suivante / terminer / rescanner)
             CapturedStructureAdapter (CapturedStructure → StructureInput)          iOS
Domain/      StructureInput, HouseBuilder (ScanInput[] + StructureInput → House), StoryDetector
Storage/     HousePackage (.housescan), HouseRecord, RoomStore → LibraryStore (pièces + maisons)
Viewer/      PlanSceneBuilder : couleur par pièce, isolation, sélecteur de niveau (déjà « house-ready »)
Export/      PlanRenderer multipage, SVG/DXF calques par niveau, PlanMeshBuilder groupes par pièce
UI / MacUI   Bibliothèque à deux niveaux (maison › pièces), écran de fusion manuelle (F37)
```

Points d'attention : la fusion manuelle (F37) est la seule fonctionnalité qui écrit dans `FloorPlan.transform` depuis l'interface ; les exporteurs n'ont rien à savoir.

## 6. Tests

- Fixtures : deux `scan.json` v1 + une `structure.json` synthétique (deux pièces mitoyennes, un mur partagé) ; une maison à deux niveaux.
- `HouseBuilderTests` (transforms, mur partagé dédoublonné, surfaces), `StoryDetectorTests`, `HousePackageTests` (aller-retour, compatibilité `.roomscan` v1), `PlanRendererTests` multipage, `DXFExporterTests` calques par niveau, `PlanMeshBuilderTests` groupes par pièce.
- Terrain : appartement 3 pièces puis maison à étage ; mesurer la dérive (écart entre deux mesures du même mur depuis deux pièces).

## 7. Phases proposées

1. Domain + fixtures (HouseBuilder, StoryDetector, StructureInput) — TDD, sans device.
2. Stockage `.housescan` + bibliothèque à deux niveaux (iPhone + Mac).
3. Capture multi-pièces + fusion Apple (device obligatoire).
4. Visualiseur maison (couleurs, isolation, niveaux, AR 1:100).
5. Exports maison (multipage, calques, groupes).
6. Fusion manuelle (F37), puis v2.x (glTF, nord, impérial, ARWorldMap, iPad).

## 8. Questions ouvertes pour Vincent

1. Faut-il garder la possibilité de **scanner une pièce seule** (v1) comme mode par défaut, la maison étant un mode « avancé » ? (Proposition : oui.)
2. Escaliers et couloirs : les modéliser comme des pièces ordinaires ou les ignorer ? (Proposition : pièces ordinaires, section « Couloir » / « Escalier » ajoutée au nommage.)
3. Priorité entre glTF (interop web / Blender) et la fusion manuelle F37 ?
