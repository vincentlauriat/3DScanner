# Architecture — 3D Scanner (miroir français)

**Plateformes :** iPhone (iOS 18+, LiDAR) scanne, visualise, exporte · Mac (macOS 15+) visualise, mesure, exporte, imprime, se met à jour via Sparkle · iCloud Drive synchronise les deux et expose les fichiers aux apps tierces. Une seule base de code, deux cibles XcodeGen (`RoomScanner`, `RoomScannerMac`), une dépendance SPM (Sparkle, Mac seulement). Dépôt public `vincentlauriat/3DScanner`, landing page GitHub Pages (`/docs`).

_Source de vérité : `ARCHITECTURE_EN.md`. Éditer les deux dans le même tour._

## Vue d'ensemble

```
UI SwiftUI ─▶ RoomCaptureView (Apple RoomPlan) ─▶ CapturedRoom
                                                     │
                                          FloorPlanBuilder
                                                     ▼
                        House { Story { [FloorPlan] } }  (pivot, Swift pur ; v1 = 1 pièce)
                                                     │
        ┌──────────────┬──────────────┬──────────────┼──────────────┬──────────────┐
   PlanRenderer     SVGExporter   DXFExporter   USDZExporter   JSONExporter   PlanSceneBuilder
   (PDF / PNG /                                 └▶ ModelIOConverter            └▶ RealityView (SwiftUI)
    texture sol)                                    (OBJ/STL/PLY)                 3D orbite · 2D zénith · AR (iOS)
                                                     │
                                        ExportService ─▶ ShareLink
                                                     │
                RoomStore ─▶ StorageLocation (conteneur iCloud │ repli local)
                  <conteneur>/Documents/Rooms/<uuid>.roomscan  ·  <conteneur>/Documents/Exports/<Pièce>/
                  UbiquityMonitor (NSMetadataQuery, téléchargement, conflits)  ⇄  iPhone ↔ Mac ↔ Fichiers / Finder
```

## Couches

| Couche | Dossier | Responsabilité | Dépend de |
|---|---|---|---|
| App | `RoomScanner/App` | Point d'entrée, état global observable, injection de dépendances | UI, Storage |
| Scan (iOS seulement) | `RoomScanner/Scan` | Enveloppe `RoomCaptureView`, **possède l'`ARSession` injectable** (repère partagé pour le multi-pièces v2), delegate → `CapturedRoom`, traduction des erreurs | RoomPlan, ARKit |
| Domain | `RoomScanner/Domain` | `ScanInput` (instantané neutre), types pivots `FloorPlan` / `House` / `Story`, `FloorPlanBuilder` (ScanInput → projection 2D), `WallGeometry` (boîtes de murs / panneaux partagés par le visualiseur et l'export de maillage), `Measurements`, `RoomNaming` | Foundation, simd uniquement |
| Viewer | `RoomScanner/Viewer` | `PlanSceneBuilder` (House → entités RealityKit), `ViewerView` (`RealityView` SwiftUI, commune iOS/macOS), `ViewerMode` (caméra 3D / 2D zénith), `ARPlacementController` (iOS : `SpatialTrackingSession`, ancres de plan, 1:20 / 1:50 / 1:1), `ViewerControls` | Domain, RealityKit, Export (texture sol via `PlanRenderer`) |
| Export | `RoomScanner/Export` | `ExportFormat` (groupes, `UTType`), `ExportService` (dossier temporaire, noms de fichiers assainis, `availableFormats`), `PlanRenderer` (PDF/PNG/vignette/texture sol), `SVGExporter`, `DXFExporter` ; USDZ copié du paquet ; `PlanMeshBuilder` + `MeshWriters` (OBJ/STL/PLY depuis le plan), `ModelIOConverter` (maillage du scan) | Domain, Core Graphics, Model I/O, RoomPlan (USDZ) |
| Storage | `RoomScanner/Storage` | `RoomStore` (CRUD des paquets `.roomscan`, activation/bascule iCloud, import, exports vers `Exports/<Pièce>/`), `RoomPackage` (UTType, `NSFileCoordinator`), `StorageLocation` (racine iCloud ou locale), `RoomRecord`, `CloudAvailability` (résolution du conteneur hors main thread, migration `setUbiquitous`), `UbiquityMonitor` (`NSMetadataQuery` → `CloudItemStatus`, téléchargement auto), `ConflictResolver` (`NSFileVersion`, la plus récente gagne, copie « (conflit) » sous nouvel UUID) | Domain, Export (vignette), Foundation |
| Sync | `RoomScanner/Sync` | `UbiquityMonitor` (liste live `NSMetadataQuery`, téléchargement à la demande, état par pièce), `CloudAvailability` (bascule iCloud ↔ local, migration), `ConflictResolver` (`NSFileVersion`) | Storage, Foundation |
| MacUI | `RoomScanner/MacUI` (cible macOS uniquement) | `MacRootView` (split view), `MacMenuCommands` (⌘E exporter, ⌘P imprimer, Révéler dans le Finder), `PrintController`, `DragExportProvider` (`NSItemProvider`), `OpenWithMenu` (`NSWorkspace`), `MacEmptyStateView` | UI, Export, AppKit |
| UI | `RoomScanner/UI` | Écrans SwiftUI : liste, détail (Plan 2D / 3D / Mesures), feuille d'export, écrans d'erreur, réglages | App, Domain, Export, Storage, QuickLook |

Règles : **Domain, Export, Storage et Sync n'importent jamais SwiftUI, UIKit ni AppKit** ; dans Viewer, `PlanSceneBuilder` est du RealityKit pur (testable), seuls `ViewerView`/`ViewerControls` sont SwiftUI ; Export ne dépend de RoomPlan que dans `USDZExporter` ; `PlanRenderer` est en Core Graphics pur (`CGContext` PDF et bitmap) pour rendre à l'identique sur les deux plateformes ; `Scan/` et `ARPlacementController` sont exclus de la cible macOS (RoomPlan n'existe pas sur macOS, vérifié).
Tout ce qui est sous l'UI est testable sur simulateur à partir de fixtures JSON.

## Types clés

- `CapturedRoom` (Apple, `Codable`) — persisté tel quel dans `room.json` ; source de vérité pour la fusion v2. **Lisible sur iOS seulement** (RoomPlan n'existe pas sur macOS).
- `ScanInput` — instantané neutre d'un scan (`ScanSurface`/`ScanObject` : catégorie, `dimensions`, `transform` simd, confiance, parent, coins). Produit par `CapturedRoomAdapter` (`Scan/`, iOS) ; seule entrée de `FloorPlanBuilder` ; ce que les tests et fixtures utilisent sur les deux plateformes. Persisté en `scan.json`.
- `House` — `stories: [Story]`, `Story` — `index, rooms: [FloorPlan]`. Tous les renderers, le scene builder et les exporteurs prennent une `House` ; en v1 elle contient toujours une pièce (D14).
- `FloorPlan` — `walls: [Wall]`, `openings: [Opening]`, `objects: [PlacedObject]`, `floorPolygon: [Point2D]`, `ceilingHeight: ClosedRange<Double>`, `bounds`, `transform` (placement dans le repère maison, identité en v1). Mètres, `Double`, `Codable`, `Equatable`. Persisté en `plan.json` (avec `schemaVersion`) pour que le Mac le lise sans RoomPlan ; recalculé depuis `room.json` sur iPhone quand le schéma change.
- `RoomMeasurements` — surface (lacet), périmètre, hauteur min/max, listes par élément.
- `ExportFormat` — `pdf, png, svg, dxf, usdzParametric, usdzMesh, obj, stl, ply, json, zip` avec `UTType`, extension, libellé localisé.
- `RoomRecord` — `meta.json` : `id, name, createdAt, label, areaM2, storyIndex, schemaVersion`.
- `RoomPackage` — le paquet `.roomscan` (UTType `fr.vincentlauriat.roomscanner.room`, conforme à `com.apple.package`) : `room.json`, `room.usdz`, `meta.json`, `thumbnail.png`. Vu comme un seul fichier dans Fichiers/Finder ; double-clic ouvre l'app Mac ; envoyable par AirDrop.
- `StorageLocation` — protocole sur la racine de stockage : conteneur iCloud (`iCloud.fr.vincentlauriat.roomscanner`) si `ubiquityIdentityToken != nil`, sinon Documents local.

## Conventions de coordonnées

- RoomPlan : Y vers le haut, sol = plan XZ, mètres. `transform` (4×4) + `dimensions` (largeur, hauteur, profondeur).
- Segment de mur : centre `(t.x, t.z)`, direction = colonne 0 du `transform` projetée sur XZ ; extrémités = centre ± dir × largeur/2.
- Plan 2D : `x_plan = x_room`, `y_plan = −z_room` (vue de dessus). Épaisseur graphique des murs : 0,10 m constant (non mesurée par RoomPlan).
- Hauteur d'allège = `(t.y − hauteur/2) − y_sol`.

## Visualiseur RealityKit (D13)

- **`RealityView`** SwiftUI (iOS 18+ / macOS 15+ — la raison des cibles de déploiement), un seul composant partagé par les deux plateformes. `content.camera = .virtual` pour les modes 3D et 2D avec les contrôles intégrés `realityViewCameraControls(.orbit)` / `.pan` + `.dolly` ; `content.camera = .spatialTracking` pour l'AR sur iOS (passthrough caméra, `SpatialTrackingSession`, `AnchorEntity(.plane(.horizontal, …))`).
- Scène **paramétrique**, construite depuis `House` par `PlanSceneBuilder` : une entité racine par maison, une enfant par pièce (positionnée par `FloorPlan.transform`) ; murs = `generateBox` (longueur × hauteur × 0,10 m), murs avec ouvertures découpés en 3 boîtes + panneau (porte : boîte fine brune ; fenêtre : boîte bleue translucide) ; sol = `generatePlane` texturé (`UnlitMaterial`) avec le PNG du plan 2D produit par `PlanRenderer` ; objets = boîtes grises translucides + libellé ; cotes 3D en option.
- Modes : **3D** (`.virtual`, contrôles orbite), **2D** (`.virtual`, `PerspectiveCamera` au zénith, murs aplatis à 0,02 m, pan/dolly seulement), **AR** (iOS seulement — `.spatialTracking`, ancres de plans horizontaux, toucher pour poser à 1:20 / 1:50 / 1:1, glisser / pivoter à deux doigts). Changer de mode ne touche que `content.camera`, la caméra virtuelle et la visibilité des murs ; les entités sont construites une fois.
- QuickLook sur `room.usdz` conservé en bouton secondaire « Aperçu rapide ».

## Spécification des exports (résumé)

| Format | Implémentation | Unités |
|---|---|---|
| PDF | `PlanRenderer.pdfData` — `CGContext` PDF (Core Graphics / Core Text), A4 paysage, échelle standard (1:20/25/50/100), cartouche ; sert aussi à l'impression Mac | pt |
| Texture sol | `PlanRenderer` mode « texture » (sans cartouche), consommé par `PlanSceneBuilder` | px |
| PNG | `PlanRenderer.pngData` — `CGContext` bitmap @3× + `CGImageDestination` | px |
| SVG | `SVGExporter`, écrivain texte, `viewBox` en mm (y inversé), `<g id>` floors/objects/walls/doors/windows/openings/dimensions/text, flèches `marker`, arc de porte `<path>` | mm |
| DXF | `DXFExporter` R12 ASCII : `HEADER` (`$ACADVER` AC1009, `$INSUNITS`=6, `$EXTMIN/MAX`), `TABLES` LTYPE/LAYER (WALLS, DOORS, WINDOWS, OPENINGS, FLOOR, OBJECTS, DIMENSIONS, TEXT)/STYLE, `ENTITIES` (murs et objets en `POLYLINE` fermées, `ARC` de porte, cotes `LINE` + ticks + `TEXT` centré) | m |
| USDZ | `CapturedRoom.export(to:exportOptions:)` au scan : `.parametric` → `room.usdz`, `.mesh` → `room-mesh.usdz` ; les exports les copient (Model I/O ne sait pas écrire d'USDZ, vérifié) | m |
| OBJ/STL/PLY | par défaut : `PlanMeshBuilder` (`TriangleMesh` depuis `House` : boîtes de murs via `WallGeometry`, panneaux portes/fenêtres, dalle polygonale, objets ; groupes walls/doors/windows/floor/objects) + `MeshWriters` (OBJ texte, STL binaire, PLY ASCII) ; option « maillage du scan » : `ModelIOConverter` (`MDLAsset(url: room-mesh.usdz).export(to:)`), hors main thread | m, y haut, z = −y_plan |
| JSON | contenu de `plan.json` (`FloorPlan`, `RoomPackage.encoder`) — lisible sur les deux plateformes, contrairement au `room.json` Apple | m |
| ZIP | tout ce qui précède + README.txt | — |

## Organisation du stockage et synchronisation iCloud (D6, D16, D17)

```
<racine>/Documents/                    racine = conteneur iCloud (affiché « iCloud Drive / 3D Scanner ») ou repli local
  Rooms/<uuid>.roomscan/               paquet = un seul fichier dans Fichiers / Finder
    room.json       CapturedRoom (source de vérité ; lisible sur iOS seulement)
    scan.json       ScanInput (instantané neutre)
    plan.json       FloorPlan (schemaVersion) — lu par le Mac et les exporteurs
    room.usdz       export paramétrique, écrit à la sauvegarde
    room-mesh.usdz  maillage brut du scan (optionnel, capture iPhone seulement)
    meta.json       RoomRecord
    thumbnail.png   aperçu du plan 600×400
  Exports/<Nom de la pièce>/<Nom>.pdf|dxf|svg|usdz|obj…   « Enregistrer dans iCloud Drive » — lisible par toute app 2D/3D sur les deux appareils
```
- Racine choisie au lancement par `StorageLocation` ; migration local → iCloud proposée quand iCloud devient disponible.
- Liste live via `NSMetadataQuery` (portée documents ubiquitaires, `*.roomscan`), badge d'état d'après les clés downloading/uploaded ; téléchargement à la demande via `startDownloadingUbiquitousItem`.
- Toute lecture/écriture passe par `NSFileCoordinator` ; un paquet est écrit en une seule opération coordonnée pour arriver complet sur l'autre appareil.
- Conflits (`NSFileVersion`) : la plus récente gagne, l'autre est conservée en `<nom> (conflit).roomscan` — un scan n'est jamais perdu.
- Info.plist des deux cibles : `NSUbiquitousContainers` avec `NSUbiquitousContainerIsDocumentScopePublic = true`, `NSUbiquitousContainerName = "3D Scanner"` ; `UTExportedTypeDeclarations` pour `.roomscan` ; Mac ajoute `CFBundleDocumentTypes`.
- Entitlements : iCloud Documents + conteneur `iCloud.fr.vincentlauriat.roomscanner` (les deux — créé automatiquement par `xcodebuild -allowProvisioningUpdates`, comme pour TheNews) ; Mac ajoute App Sandbox, fichiers choisis par l'utilisateur r/w, impression, client réseau, exceptions Sparkle `mach-lookup` (`-spks`, `-spki`) ; un `-Release.entitlements` fixe `icloud-container-environment = Production` pour le DMG.
- Les exports temporaires vivent dans `tmp/` et sont regénérés à la demande. iOS garde `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` pour le dossier local de repli.

## Gestion des erreurs

`enum AppError: LocalizedError` — `unsupportedDevice`, `cameraDenied`, `scanFailed(RoomPlan.Error)`,
`exportFailed(format, underlying)`, `storageFailed`, `cloudUnavailable`, `downloadFailed`, `conflictResolved(kept:)`. `room.json` est écrit **avant** toute conversion :
un échec d'export ne perd jamais un scan. Les erreurs RoomPlan sont traduites en messages localisés lisibles.

## Auto-update Mac (D18)

Sparkle 2 (SPM, cible Mac seulement). `SUFeedURL` → `appcast.xml` à la racine du dépôt sur `main` (raw GitHub) ; `SUPublicEDKey` embarquée ; la clé privée EdDSA vit dans le trousseau de connexion (compte `RoomScanner`), générée **une seule fois** et sauvegardée — jamais régénérée. App sandboxée → `SUEnableInstallerLauncherService = YES`. `Scripts/release.sh` (issu de `Templates/Scripts/release-full.sh`) construit, signe (Developer ID, hardened runtime), notarise, agrafe, empaquette le DMG dans `release/`, lance `sign_update` et réécrit `appcast.xml`.

## Livraison (D19)

Dépôt public `vincentlauriat/3DScanner`. Une branche par phase `feat/phase-N-<nom>` → PR → merge sur `main`, enchaînées sans validation intermédiaire ; tags et GitHub Releases toujours confirmés par Vincent. Landing page `docs/index.html` (GitHub Pages depuis `/docs`, trilingue, `assets/base.css` du hub), une ligne dans le hub `vincentlauriat.github.io` et une entrée dans le README du profil.

## Stratégie de test

- Simulateur **et macOS** (mêmes sources de test sur les deux) : tests unitaires du Domain (fixtures + pièces synthétiques), golden files SVG/DXF,
  validation structurelle DXF, sanité PNG, `PlanSceneBuilder` (nombre/placement des entités), `RoomStore`/`RoomPackage` sur un `StorageLocation` local temporaire, `ConflictResolver` avec versions simulées.
- Appareil : checklist manuelle (précision vs mètre ruban < 2 %, chaque export ouvert dans un lecteur
  externe : Aperçu, LibreCAD/QCAD, Blender, Fichiers ; aller-retour iCloud iPhone → Mac < 1 min, repli mode avion, import `.roomscan` par AirDrop ; Mac : double-clic, ⌘P, glisser-déposer, Ouvrir avec).

## Journal des décisions

Voir §3 de la spécification (`docs/superpowers/specs/2026-09-05-3dscanner-design.md`) : D1 RoomCaptureView,
D2 SwiftUI, D3 modèle pivot, D4 écrivains 2D maison, D5 Model I/O pour OBJ (glTF en v2), D6 stockage fichiers,
D7 une pièce en v1, D8 feuille de partage, D9 unités métriques, D10 pas de dépendance SPM, D11 fr/en, D12 nommage (à confirmer),
D13 visualiseur RealityKit `ARView` (3D / 2D / AR) construit paramétriquement depuis `House`, D14 agrégat `House` + `ARSession` partagée dès la v1 (prêt pour la maison),
D15 compagnon Mac sur la base de code partagée (deux cibles, renderer Core Graphics pur, pas de scan sur Mac), D16 conteneur iCloud Drive comme stockage principal avec repli local (CloudKit écarté : n'expose aucun fichier aux apps tierces), D17 type paquet `.roomscan`,
D18 auto-update Sparkle sur Mac, D19 dépôt public + branche par phase + landing page.

## Préparation v2 (maison entière)

- Flux de scan v2 : « Scanner la maison » conserve un seul `ARSession` entre les pièces (`RoomCaptureSession(arSession:)`, `stop(pauseARSession: false)`) pour que toutes les `CapturedRoom` partagent un repère → `StructureBuilder.capturedStructure(from:)` → `CapturedStructure` → `House` à N pièces / niveaux.
- Rien ne change en aval : `PlanRenderer`, `PlanSceneBuilder` et chaque exporteur itèrent déjà sur `house.allRooms` ; la coloration par pièce s'appuie sur la hiérarchie d'entités.
- Stockage v2 : ajout de `Documents/Houses/<uuid>/house.json` (ids de pièces + transforms + structure fusionnée) ; les dossiers de pièces restent inchangés.
