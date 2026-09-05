# 3D Scanner — Spécification de conception

| | |
|---|---|
| **Date** | 2026-09-05 |
| **Statut** | **Validé par Vincent le 2026-09-05** — exécution autonome, une branche `feat/` par phase, sans re-demander (sauf tags/releases) |
| **Auteur** | Vincent Lauriat (avec Claude) |
| **Cible** | iPhone Pro (LiDAR), **iOS 18+** — scan, visualisation, export · **Mac (macOS 15+)** — visualisation, mesures, export, auto-update Sparkle · **iCloud Drive** — synchronisation et partage |
| **Chemin décidé** | Approche A — `RoomCaptureView` clé en main + moteur d'export maison + **visualiseur RealityKit (`ARView`)**, architecture prête pour la maison entière (v2) + **app Mac compagnon à codebase partagé** + **iCloud Drive** comme pont iPhone ↔ Mac ↔ apps tierces + visualiseur **`RealityView`** (iOS 18 / macOS 15) + **Sparkle** sur Mac + dépôt GitHub public avec landing page |

---

## 1. Objectif

Une application iPhone qui **scanne une pièce de la maison avec le LiDAR**, en déduit
**un plan 2D coté** (murs, portes, fenêtres, dimensions en centimètres, surface au sol)
et **un modèle 3D**, puis **partage** ces résultats vers n'importe quelle application
2D (PDF, SVG, DXF pour la CAO) ou 3D (USDZ, OBJ) via la feuille de partage iOS.

Une **application Mac compagnon**, construite sur le même code, retrouve automatiquement les pièces
scannées via **iCloud Drive**, les affiche (plan 2D coté, modèle 3D, mesures) sur grand écran et les
exporte/partage vers les logiciels 2D/3D du Mac. Le dossier iCloud « 3D Scanner » est visible dans
Fichiers (iPhone) et dans le Finder (Mac) : n'importe quelle application 2D/3D, sur l'un ou l'autre
appareil, y lit directement les plans exportés.

**Ce que l'utilisateur doit pouvoir faire en v1, de bout en bout :**

1. Ouvrir l'app, appuyer sur « Scanner une pièce ».
2. Se laisser guider par l'écran de scan Apple (rapprochez-vous, ralentissez…).
3. Appuyer sur « Terminer » → voir le plan 2D coté, le modèle 3D (visualiseur RealityKit : orbite, vue de dessus, **mode AR** pour poser la maquette sur une table ou la superposer à la vraie pièce) et la liste des mesures.
4. Nommer la pièce (ou garder le nom proposé : Salon, Chambre…).
5. Exporter dans le format voulu → feuille de partage → AirDrop / Fichiers / Mail / app tierce.
6. Retrouver la pièce dans la liste, la ré-exporter plus tard sans rescanner.
7. Ouvrir l'app sur le Mac : la pièce est déjà là (iCloud), la visualiser en 3D/2D avec ses mesures, l'exporter (menu Fichier), l'imprimer, la glisser-déposer dans SketchUp/Blender/Illustrator.
8. Choisir « Enregistrer dans iCloud Drive » : le PDF/DXF/USDZ apparaît dans `iCloud Drive/3D Scanner/Exports/` sur les deux appareils, prêt à être ouvert par toute application.

---

## 2. Contexte et contraintes

### 2.1 Matériel et OS
- **Appareil** : iPhone 15/16/17 Pro (LiDAR obligatoire ; RoomPlan refuse les modèles non-Pro).
- **iOS minimum : 18.0** (décision Vincent). Justification : `RealityView` SwiftUI et `realityViewCameraControls` sont `@available(iOS 18.0)` ; cela couvre aussi `Surface.polygonCorners`, `CapturedRoom.sections` et `StructureBuilder` (iOS 17). L'iPhone 15/16/17 Pro de Vincent est compatible.
- **Le simulateur ne peut pas exécuter RoomPlan** (pas de LiDAR, pas d'ARKit). Conséquences :
  tout le moteur de conversion/export doit être testable **hors device** à partir de fixtures
  JSON ; l'écran de scan se teste uniquement sur iPhone.

### 2.1 bis Mac compagnon
- **macOS 15.0 (Sequoia) minimum** (`RealityView` + `realityViewCameraControls` sont macOS 15+), Apple Silicon et Intel. Le Mac de Vincent est sous macOS 27.
- **RoomPlan n'existe pas sur macOS** (vérifié : framework absent du SDK) → le scan reste sur iPhone ; le Mac visualise, mesure, exporte, imprime.
- **RealityKit `RealityView` existe sur macOS 15** (vérifié) avec caméra virtuelle et contrôles orbite intégrés ; pas de caméra AR sur Mac → même visualiseur, sans l'onglet AR.
- Model I/O, QuickLook, Core Graphics : présents → exports identiques.

### 2.2 Chaîne de build
- Xcode 27.0 (SDK iOS 27.0), `xcodegen` 2.46 — projet `.xcodeproj` généré, non versionné.
- Signature automatique avec l'équipe Apple Developer `KFLACS69T9` (déjà en place chez Vincent) ; Mac : certificat Developer ID + notarisation via le `release.sh` standard de Vincent (skill `macos-app-release`).
- Une seule dépendance tierce (SPM) : **Sparkle 2** (auto-update, cible Mac uniquement). Tout le reste repose sur RoomPlan, ARKit, RealityKit, Model I/O,
  Core Graphics, SwiftUI, QuickLook, Foundation (iCloud Drive / ubiquity).

### 2.3 Framework central : RoomPlan (Apple)
Vérifié dans l'interface Swift du SDK iOS 27 :

| Élément | Rôle | Dispo |
|---|---|---|
| `RoomCaptureView` | Vue UIKit complète : caméra AR, guidage, rendu 3D live, bouton terminer | iOS 16 |
| `RoomCaptureViewDelegate` | `captureView(shouldPresent:error:)` / `captureView(didPresent:error:)` | iOS 16 |
| `RoomCaptureSession.isSupported` | Détection LiDAR/compatibilité au runtime | iOS 16 |
| `CapturedRoom` (`Codable`, `Sendable`) | Résultat : `walls`, `doors`, `windows`, `openings`, `floors`, `objects`, `sections`, `story` | iOS 16/17 |
| `CapturedRoom.Surface` | `dimensions` (m), `transform` (4×4), `category`, `confidence`, `polygonCorners`, `parentIdentifier`, `curve` | iOS 16/17 |
| `CapturedRoom.Object` | `category` (table, sofa, bed, toilet, sink…), `dimensions`, `transform` | iOS 16 |
| `CapturedRoom.Section.label` | `livingRoom`, `bedroom`, `bathroom`, `kitchen`, `diningRoom`, `unidentified` | iOS 17 |
| `CapturedRoom.export(to:exportOptions:)` | USDZ natif ; options `.parametric`, `.mesh`, `.model` | iOS 16/17 |
| `StructureBuilder.capturedStructure(from:)` | Fusion de N pièces → maison (v2) | iOS 17 |
| `RoomCaptureSession(arSession:)` + `stop(pauseARSession: false)` | Enchaîner plusieurs scans dans **un même repère** (prérequis de la fusion v2) | iOS 17 |

Système de coordonnées RoomPlan : **Y vers le haut**, le sol est le plan **XZ**, unités en **mètres**.

### 2.4 Capacités Model I/O vérifiées (proxy macOS, même framework sur iOS)
- Import : `usdz` ✔, `usd` ✔
- Export : `obj` ✔, `stl` ✔, `ply` ✔ — `gltf` ✘, `usdz` ✘

→ **OBJ, STL, PLY** sont « gratuits » depuis l'USDZ produit par RoomPlan. **glTF/GLB exige un
écrivain maison** : reporté en v2.

### 2.5 Capacités RealityKit vérifiées (SDK iOS 27 / macOS 27)
- **`RealityView`** (SwiftUI, `_RealityKit_SwiftUI`) : `@available(iOS 18.0, macOS 15.0)` ✔ — c'est ce qui motive iOS 18 / macOS 15 minimum.
- `RealityViewCameraContent.camera` : **`.virtual`** (caméra virtuelle, visualiseur 3D classique) ou **`.spatialTracking`** (caméra AR avec passthrough et suivi ARKit, iOS) ✔ → un seul composant pour les modes 3D, 2D et AR.
- `.realityViewCameraControls(CameraControls)` (`.orbit`, `.pan`, `.dolly`, `.tilt`) : orbite/zoom **fournis par le framework**, iOS et macOS ✔ → plus de contrôleur de caméra maison pour le mode 3D.
- `SpatialTrackingSession` + `AnchorEntity(.plane(.horizontal, classification: .table/.floor, minimumBounds:))` : détection de plans et ancrage pour le mode AR ✔.
- `MeshResource.generateBox(width:height:depth:)`, `generatePlane`, `generateText`, `TextureResource.load(contentsOf:)` : construction **paramétrique** de la scène depuis `FloorPlan`, sol texturé avec le plan 2D rendu par `PlanRenderer` ✔.
- `Entity.load(contentsOf:)` charge un USDZ → mode « mesh brut » optionnel depuis `room.usdz` ✔.
- `ARView` (UIKit/AppKit) existe aussi mais n'est plus nécessaire.

### 2.6 iCloud Drive (Foundation) — vérifié
- `FileManager.url(forUbiquityContainerIdentifier:)`, `startDownloadingUbiquitousItem(at:)`, `NSMetadataQuery`, `NSFileCoordinator` / `NSFilePresenter` : disponibles iOS 5+ / macOS 10.7+.
- `NSUbiquitousContainers` + `NSUbiquitousContainerIsDocumentScopePublic = true` dans l'`Info.plist` exposent le conteneur comme dossier **« 3D Scanner »** dans Fichiers (iOS) et iCloud Drive (Finder). C'est ce qui permet le partage avec les applications tierces des deux côtés sans code supplémentaire.
- Entitlements requis : `com.apple.developer.icloud-services = [CloudDocuments]`, `com.apple.developer.icloud-container-identifiers = [iCloud.fr.vincentlauriat.roomscanner]`, `com.apple.developer.ubiquity-container-identifiers` ; Mac : App Sandbox activé (exigé par la capacité iCloud).

---

## 3. Décisions d'architecture (ADR condensés)

| # | Décision | Alternatives écartées | Raison |
|---|---|---|---|
| D1 | **`RoomCaptureView` clé en main** (approche A) | B : `RoomCaptureSession` + `ARView` custom ; C : mesh ARKit brut | L'UX de scan Apple est éprouvée ; le besoin réel est dans les plans et le partage, pas dans l'écran de scan. B double le code sans valeur ajoutée pour l'utilisateur. |
| D2 | **SwiftUI** pour toute l'app ; `UIViewRepresentable` uniquement autour de `RoomCaptureView` (le visualiseur est du SwiftUI natif via `RealityView`) | UIKit complet | Cohérence avec les autres projets de Vincent ; `ShareLink`, `NavigationStack`, `Observable` disponibles en iOS 17. |
| D3 | **Modèle pivot `FloorPlan`** indépendant de RoomPlan, alimenté par un instantané neutre **`ScanInput`** (surfaces/objets : `dimensions`, `transform` simd, catégorie, confiance, parent) produit par l'adaptateur `CapturedRoom → ScanInput` dans `Scan/` (iOS) | Exporter directement depuis `CapturedRoom` ; Domain important RoomPlan | **RoomPlan n'existe pas sur macOS** : le Domain, les tests et les fixtures ne peuvent dépendre que de types à nous. Découple les exporteurs du framework Apple ; testable sur Mac *et* simulateur ; accueille d'autres sources (fusion maison, édition manuelle). *(Précisé en phase 1.)* |
| D4 | **Exports 2D écrits à la main** : PDF/PNG via Core Graphics, SVG et DXF R12 en texte | Bibliothèque DXF tierce | DXF R12 est un format texte simple (lignes, textes, calques) ; zéro dépendance ; maîtrise totale. |
| D5 | **Exports 3D** : USDZ natif RoomPlan ; OBJ (+ STL/PLY en bonus) via Model I/O | glTF en v1 | Model I/O n'exporte pas glTF (vérifié). Un écrivain GLB maison est faisable en v2 car nous possédons la géométrie paramétrique. |
| D6 | **Persistance fichiers** : un scan = un paquet autonome `<racine>/Rooms/<uuid>.roomscan` (`room.json` = `CapturedRoom` Apple brut, **`scan.json` = `ScanInput`** et **`plan.json` = `FloorPlan`** lisibles sans RoomPlan, USDZ, méta, vignette), racine iCloud ou locale (voir D16, D17). `room.json` reste la source de vérité pour la v2 (`StructureBuilder`) ; `plan.json` porte `schemaVersion` et est recalculé sur iPhone quand le builder évolue | SwiftData / Core Data ; CloudKit | Un fichier par scan, visible dans Fichiers/Finder, synchronisable tel quel par iCloud Drive. YAGNI : pas de requêtes complexes. |
| D7 | **Une pièce à la fois** en v1 ; maison entière en v2 via `StructureBuilder` | Multi-pièces dès la v1 | La fusion (dérive, relocalisation, murs superposés) est la partie difficile ; le modèle `FloorPlan` est conçu pour N pièces dès maintenant pour ne rien réécrire. |
| D8 | **Partage via la feuille iOS** (`ShareLink` / `UIActivityViewController`) | Intégrations directes (Dropbox, etc.) | Couvre AirDrop, Fichiers, Mail, Messages et toute app installée capable d'ouvrir le type de fichier. |
| D9 | **Unités : centimètres** sur les plans, m² pour les surfaces ; option pouces/pieds différée | Choix d'unité en v1 | Vincent est en France ; l'option sera triviale à ajouter dans le modèle (`MeasurementFormatter`). |
| D10 | **Une seule dépendance SPM : Sparkle 2** (cible Mac, voir D18). Aucune autre | Packages utilitaires | Réduit la surface de maintenance ; tout le reste est dans le SDK. |
| D11 | **Localisation fr/en** dès le départ via `String(localized:)` + `Localizable.xcstrings` | fr seul | Coût quasi nul au démarrage, très cher à rattraper. |
| D12 | **Nom de module `RoomScanner`**, nom affiché « 3D Scanner », bundle **`fr.vincentlauriat.roomscanner`** (identique iOS et Mac, comme TheNews), conteneur iCloud **`iCloud.fr.vincentlauriat.roomscanner`** créé automatiquement par `xcodebuild -allowProvisioningUpdates` (signature automatique, équipe `KFLACS69T9`) — comme pour TheNews | `3DScanner` ; `fr.lauriat.*` ; création manuelle du conteneur | Un module Swift ne peut pas commencer par un chiffre ; convention de bundle déjà en place chez Vincent ; l'automatisation évite le geste manuel dans le portail. **Validé.** |
| D13 | **Visualiseur RealityKit `RealityView`** (SwiftUI natif, iOS 18 / macOS 15) pour les plans 2D et 3D, scène construite **paramétriquement depuis `House`/`FloorPlan`** (murs = boîtes, ouvertures = panneaux, sol = plan texturé avec le rendu 2D) ; trois modes : **3D orbite** (`camera = .virtual` + `realityViewCameraControls(.orbit)`), **2D vue de dessus** (`.virtual`, caméra au zénith verrouillée, `.pan`/`.dolly`), **AR** (`camera = .spatialTracking`, maquette posée sur une surface ou superposition 1:1 — iOS). QuickLook conservé comme bouton secondaire « Aperçu rapide » | QuickLook seul ; SceneKit ; `ARView` wrappé (iOS 17) | Demande explicite de Vincent, qui a accepté iOS 18 minimum pour bénéficier de `RealityView` : un seul composant SwiftUI pour les trois modes, caméra orbite fournie, même code iOS/Mac. Une scène paramétrique (et non l'USDZ) permet de colorer par pièce, d'afficher les cotes en 3D, de composer N pièces en v2 et de basculer 2D/3D sans recharger. |
| D15 | **App Mac compagnon à codebase partagé** : un seul dossier source, deux cibles XcodeGen (`RoomScanner` iOS 18 / `RoomScannerMac` macOS 15) ; `Scan/` et `ARPlacementController` exclus de la cible Mac ; `PlanRenderer` écrit en **Core Graphics pur** (`CGContext` PDF et bitmap) pour être bi-plateforme ; visualiseur = la même `RealityView` (modes 3D/2D partout, AR sur iOS) ; le Mac ajoute menu Fichier › Exporter, impression, glisser-déposer, « Ouvrir avec… » | App Mac séparée ; Mac Catalyst ; pas d'app Mac (Finder seul) | Demande de Vincent ; c'est le pattern déjà utilisé dans ses autres projets (`AppKitTemplate`). Catalyst donne une UI iPhone sur Mac, moins bonne. Domain/Export/Viewer sont déjà sans UIKit. |
| D16 | **iCloud Drive (conteneur ubiquitaire `iCloud.fr.vincentlauriat.roomscanner`) comme stockage principal**, dossier public « 3D Scanner » : `Documents/Rooms/<uuid>.roomscan` (paquets) + `Documents/Exports/` ; repli local automatique si iCloud est indisponible ; téléchargement à la demande ; `NSMetadataQuery` pour lister, `NSFileCoordinator` pour lire/écrire | CloudKit (base privée + `CKAsset`) ; Dropbox/Drive ; AirDrop seul | Vincent veut partager avec des apps 2D/3D **sur iPhone et Mac** : seul un dossier iCloud Drive visible dans Fichiers/Finder le fait sans intégration par app. CloudKit n'expose aucun fichier aux tiers. Prolonge D6 (fichiers) sans changer le format. |
| D17 | **Paquet `.roomscan`** (dossier-paquet, UTType exporté `fr.vincentlauriat.roomscanner.room`, conforme à `com.apple.package`) contenant `room.json`, `room.usdz`, `meta.json`, `thumbnail.png` | Dossier nu ; fichier unique ZIP | Un paquet est vu comme **un seul fichier** dans Fichiers/Finder (pas de contenu interne exposé par erreur), double-clic sur Mac ouvre l'app, glisser-déposer AirDrop d'une pièce entière possible. |
| D18 | **Sparkle 2 pour l'auto-update de l'app Mac** (SPM `sparkle-project/Sparkle` ≥ 2.9.1, cible Mac seulement) : `SUFeedURL` → `appcast.xml` à la racine du dépôt (raw GitHub, branche `main`), `SUPublicEDKey` embarquée, clé privée EdDSA dans le trousseau (compte `RoomScanner`) **générée une seule fois et sauvegardée — jamais régénérée** ; app sandboxée → `SUEnableInstallerLauncherService = YES` + exceptions `mach-lookup` `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki` (à vérifier en phase 10) ; `Scripts/release.sh` dérivé de `Templates/Scripts/release-full.sh` (DMG, notarisation, `sign_update`, appcast) | Pas d'auto-update ; Mac App Store | Demande de Vincent ; pipeline déjà éprouvé sur MarkdownViewer et TheNews. |
| D19 | **Dépôt GitHub public `vincentlauriat/3DScanner`**, `main` protégé par convention : une branche **`feat/phase-N-<nom>` par phase → PR → merge**, enchaînées **sans re-demander** (décision Vincent) ; tags et releases toujours confirmés ; **landing page** `docs/index.html` servie par GitHub Pages (`/docs`, comme les autres projets), trilingue EN/FR/ZH-Hant avec `assets/base.css` du hub ; ligne ajoutée dans le hub `vincentlauriat.github.io` (Zone B) et dans le README du profil `vincentlauriat/vincentlauriat` | Dépôt privé ; push direct sur `main` | Demande de Vincent ; cohérent avec ses 25 autres projets publiés. |
| D14 | **Prêt pour la maison entière dès la v1** : agrégat `House { stories: [Story { rooms: [FloorPlan] }] }` consommé par le renderer, le scene builder et les exporteurs (v1 : une pièce, transform identité) ; `ScanCoordinator` possède l'`ARSession` (injectable) pour enchaîner les scans dans un même repère en v2 ; `FloorPlan.transform` réservé au placement dans le repère maison | Ajouter la maison plus tard | Éviter une réécriture des exports et du visualiseur en v2 ; le surcoût v1 est un type d'agrégat et un paramètre. |

---

## 4. Fonctionnalités

### 4.1 Périmètre v1 (livrable)

**Scan**
- F1. Contrôle de compatibilité au lancement (`RoomCaptureSession.isSupported`) avec écran explicatif si l'appareil n'a pas de LiDAR.
- F2. Demande d'accès caméra avec message clair ; écran de recours si refusé (lien vers Réglages).
- F3. Écran de scan `RoomCaptureView` plein écran avec guidage Apple (coaching activé), bouton Terminer, bouton Annuler.
- F4. Traitement du résultat, gestion des erreurs RoomPlan (pièce trop grande, texture insuffisante, appareil trop chaud, suivi perdu…).

**Résultat d'une pièce**
- F5. Nom proposé automatiquement d'après `sections.label` (Salon, Chambre, Salle de bain, Cuisine, Salle à manger, Pièce) + numéro si doublon ; renommable.
- F6. Onglet **Plan 2D** : vue de dessus vectorielle, murs épais, portes (arc d'ouverture), fenêtres (double trait), ouvertures (pointillés), cotes de chaque mur en cm, surface au sol en m², rose d'orientation nord non incluse (v2), zoom/pan.
- F7. Onglet **3D / AR** (visualiseur `RealityView`, D13) :
  - **3D** : orbite au doigt / souris, pincer ou molette pour zoomer (`realityViewCameraControls(.orbit)`), bouton recentrer ; murs, portes (cadre + panneau), fenêtres (vitrage translucide), objets (boîtes grisées + libellé), cotes des murs affichées en 3D (option).
  - **2D** : bascule vers la vue de dessus au zénith — le sol texturé avec le plan coté rendu par `PlanRenderer`, murs aplatis ; c'est le même contenu que l'export PDF, en interactif.
  - **AR** (iOS) : `camera = .spatialTracking`, détection de plans horizontaux (`SpatialTrackingSession`, `AnchorEntity(.plane)`), guidage « déplacez l'iPhone », toucher pour poser la maquette à l'échelle **1:20 / 1:50** sur une table ; mode **1:1** pour superposer le modèle à la vraie pièce (alignement manuel : glisser / pivoter).
  - Bouton secondaire « Aperçu rapide » → QuickLook sur `room.usdz` (AR Apple standard, robuste).
- F8. Onglet **Mesures** : liste structurée — surface au sol, périmètre, hauteur sous plafond (min/max), chaque mur (longueur × hauteur), chaque porte/fenêtre (largeur × hauteur, hauteur d'allège pour les fenêtres), objets détectés (catégorie + dimensions).
- F9. Indicateur de confiance par élément (haute / moyenne / basse) affiché discrètement dans Mesures.

**Export et partage**
- F10. Feuille d'export avec choix du format :
  - 2D : **PDF** (A4 paysage, échelle automatique indiquée, cartouche titre/date/surface), **PNG** (haute résolution, fond blanc), **SVG** (unités mm, calques par groupes), **DXF R12** (unités mètres, calques `WALLS` `DOORS` `WINDOWS` `OPENINGS` `OBJECTS` `DIMENSIONS` `TEXT`).
  - 3D : **USDZ** (paramétrique, avec option mesh brut), **OBJ**, **STL**, **PLY**.
  - Données : **JSON** brut `CapturedRoom` (réimportable, utile pour le support et les tests).
- F11. Chaque export ouvre la feuille de partage iOS (`ShareLink`) avec le fichier généré.
- F12. Export groupé « Tout » → archive ZIP contenant tous les formats + `README.txt` (**v1**, décision Vincent ; écrit via `NSFileCoordinator` + `Compression`/`Archive`).

**Bibliothèque**
- F13. Liste des pièces scannées (nom, date, surface, vignette du plan 2D) triée par date.
- F14. Suppression d'une pièce (swipe) avec confirmation.
- F15. Ré-export d'une pièce déjà scannée sans rescan.
- F16. Les dossiers sont visibles dans l'app **Fichiers** (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`).

**iCloud Drive (D16, D17)**
- F18. Les pièces sont stockées dans `iCloud Drive/3D Scanner/Rooms/` sous forme de paquets `.roomscan` ; synchronisation automatique iPhone ↔ Mac ; indicateur d'état par pièce (à jour · en cours · non téléchargée · conflit).
- F19. Repli local transparent si iCloud est désactivé ou hors ligne ; bannière « iCloud inactif — les pièces restent sur cet appareil » et bouton vers Réglages.
- F20. « Enregistrer dans iCloud Drive » dans la feuille d'export : écrit le fichier dans `iCloud Drive/3D Scanner/Exports/<Nom de la pièce>/` → accessible par toute app 2D/3D via Fichiers (iPhone) ou Finder (Mac).
- F21. Ouverture d'un `.roomscan` reçu (AirDrop, Fichiers, double-clic Mac) → import dans la bibliothèque.

**App Mac (D15)**
- F22. Fenêtre `NavigationSplitView` : barre latérale des pièces (nom, surface, date, état iCloud), zone de détail avec onglets Plan 2D / 3D / Mesures (mêmes vues que l'iPhone, mises en page pour grand écran).
- F23. Visualiseur `RealityView` macOS : orbite à la souris/trackpad, zoom molette/pinch (contrôles intégrés), mode 2D zénith ; pas d'onglet AR (pas de caméra AR sur Mac).
- F29. **Auto-update Sparkle** sur Mac : vérification quotidienne, menu « Rechercher les mises à jour… », installation en un clic (D18).
- F24. Menu Fichier › Exporter… (sous-menu par format) et ⌘E ; Fichier › Imprimer le plan (⌘P, PDF vectoriel) ; Fichier › Révéler dans le Finder.
- F25. Glisser-déposer : la vignette du plan ou une ligne « format » de la feuille d'export se glisse directement dans une autre app (Illustrator, SketchUp, Blender, Mail) via `NSItemProvider` (`.draggable`).
- F26. « Ouvrir avec… » : liste des applications du Mac capables d'ouvrir le format (`NSWorkspace.urlsForApplications(toOpen:)`), ouverture directe.
- F27. Partage Mac standard (`ShareLink` → `NSSharingServicePicker` : AirDrop, Mail, Messages, Notes…).
- F28. Le Mac ne scanne pas : écran d'accueil vide expliquant « Scannez avec votre iPhone, la pièce apparaît ici via iCloud ».

**Réglages (minimal)**
- F17. Langue suivie du système (fr/en), à propos, version, état iCloud, emplacement du dossier « 3D Scanner ».

### 4.2 Périmètre v2 (préparé, non livré en v1)
- Maison entière : mode « Scanner la maison » enchaînant les pièces dans **un même `ARSession`** (`stop(pauseARSession: false)`), puis `StructureBuilder.capturedStructure(from:)` → `CapturedStructure` → `House` multi-pièces, plusieurs niveaux (`story`) ; plan d'étage par niveau, visualiseur montrant toute la maison (pièces colorées), exports 2D/3D de la maison entière. Le modèle `House`, le visualiseur et les exporteurs v1 sont déjà dimensionnés pour cela (D14).
- Export **glTF/GLB** (écrivain maison depuis la géométrie paramétrique).
- Nord/orientation (boussole au moment du scan) et rose sur le plan.
- Unités impériales.
- Édition manuelle : renommer/ajuster une cote, masquer un objet.
- Export vers apps de plans (Magicplan, SketchUp) via formats déjà couverts ; IFC si demandé.
- iPad Pro (LiDAR) : mise en page adaptée.

### 4.3 Hors périmètre (explicitement)
- Reconstruction géométrique maison sans RoomPlan.
- Textures photo-réalistes du modèle 3D (RoomPlan ne les fournit pas).
- Synchronisation cloud propriétaire, comptes utilisateurs.
- Scan depuis le Mac (RoomPlan n'existe pas sur macOS).

---

## 5. Architecture

### 5.1 Vue d'ensemble

```
┌──────────────────────────────────────────────────────────────────┐
│  UI (SwiftUI)                                                     │
│  RoomListView ─▶ ScanView (RoomCaptureView wrapper) ─▶ RoomDetail │
│                                    │                 ├ Plan2DView │
│                                    │                 ├ ViewerView (RealityView 3D / 2D / AR)
│                                    │                 ├ MeasuresView
│                                    │                 └ ExportSheet│
└────────────────────────────────────┼─────────────────────────────┘
                                     ▼ CapturedRoom (Apple)
┌──────────────────────────────────────────────────────────────────┐
│  Domain                                                           │
│  FloorPlanBuilder : CapturedRoom ──▶ FloorPlan (pivot, pur Swift) │
│  House { stories[ Story { rooms[FloorPlan] } ] }  (v1 : 1 pièce) │
│  Measurements : House/FloorPlan ──▶ RoomMeasurements (cotes, m²)  │
└────────────────────────────────────┼─────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────┐
│  Viewer (RealityKit)                                              │
│  PlanSceneBuilder : House ──▶ Entities (murs, ouvertures, sol     │
│     texturé par PlanRenderer) ─▶ RealityView .virtual / .spatialTracking
└──────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────┐
│  Export                                                           │
│  PlanRenderer (Core Graphics) ─▶ PDF / PNG                        │
│  SVGExporter ─▶ .svg      DXFExporter ─▶ .dxf (R12)               │
│  USDZExporter (RoomPlan) ─▶ .usdz ─▶ ModelIOConverter ─▶ obj/stl/ply
│  JSONExporter ─▶ .json    ArchiveExporter ─▶ .zip                 │
└────────────────────────────────────┼─────────────────────────────┘
                                     ▼
┌──────────────────────────────────────────────────────────────────┐
│  Storage + Sync                                                   │
│  RoomStore ─▶ StorageLocation (iCloud ubiquity container ou local)│
│     <container>/Documents/Rooms/<uuid>.roomscan/{room.json,        │
│        room.usdz, meta.json, thumbnail.png}                       │
│     <container>/Documents/Exports/<Pièce>/<fichiers exportés>     │
│  UbiquityMonitor : NSMetadataQuery, téléchargement, conflits      │
└──────────────────────────────────────────────────────────────────┘

Plateformes : iPhone = tout ; Mac = tout sauf `Scan/` et le mode AR ; iCloud Drive relie les deux et expose
`Rooms/` et `Exports/` aux applications tierces dans Fichiers et le Finder.
```

### 5.2 Arborescence du code

```
RoomScanner/
├── App/
│   ├── RoomScannerApp.swift          # @main, injection du RoomStore
│   └── AppState.swift                # @Observable : liste, sélection, erreurs globales
├── Scan/
│   ├── RoomCaptureViewRepresentable.swift  # UIViewRepresentable + Coordinator (delegate)
│   ├── ScanView.swift                # plein écran, boutons Terminer/Annuler, overlay d'état
│   ├── CapturedRoomAdapter.swift     # CapturedRoom → ScanInput (seul endroit qui lit les types RoomPlan)
│   └── ScanCoordinator.swift         # possède l'ARSession (injectable), cycle de vie, réception CapturedRoom, erreurs
├── Domain/
│   ├── ScanInput.swift               # instantané neutre d'un scan (surfaces/objets simd) — frontière avec RoomPlan
│   ├── FloorPlan.swift               # types pivots (Codable, Equatable) — pur Swift
│   ├── House.swift                   # agrégat House / Story (v1 : une pièce, transform identité)
│   ├── FloorPlanBuilder.swift        # CapturedRoom → FloorPlan (projection XZ, cotes)
│   ├── Measurements.swift            # surface (shoelace), périmètre, hauteurs, listes
│   ├── Geometry.swift                # Point2D, Segment2D, helpers simd → 2D
│   └── RoomNaming.swift              # Section.label → nom localisé + dédoublonnage
├── Viewer/
│   ├── PlanSceneBuilder.swift        # House → entités RealityKit (murs, ouvertures, objets, sol texturé, cotes 3D) — pur RealityKit, testable
│   ├── ViewerView.swift              # RealityView SwiftUI (commun iOS/Mac) ; camera .virtual (3D/2D) ou .spatialTracking (AR, iOS) ; realityViewCameraControls
│   ├── ViewerMode.swift              # enum 3D / 2D / AR ; état (échelle AR, cotes on/off) ; caméra zénithale verrouillée pour le 2D
│   ├── ARPlacementController.swift   # iOS : SpatialTrackingSession, AnchorEntity(.plane), pose 1:20 / 1:50 / 1:1, glisser / pivoter
│   └── ViewerControls.swift          # segment 3D | 2D | AR, échelle, cotes on/off, recentrer, « Aperçu rapide » (QuickLook)
├── Export/
│   ├── ExportFormat.swift            # enum des formats, UTType, extension, libellés
│   ├── PlanRenderer.swift            # dessin Core Graphics commun PDF/PNG (échelle, cotes, cartouche)
│   ├── PDFExporter.swift
│   ├── PNGExporter.swift
│   ├── SVGExporter.swift
│   ├── DXFExporter.swift             # R12 ASCII : HEADER, TABLES(LAYER), ENTITIES(LINE, TEXT, ARC)
│   ├── USDZExporter.swift            # CapturedRoom.export(to:exportOptions:)
│   ├── ModelIOConverter.swift        # MDLAsset(url: usdz).export(to: obj/stl/ply)
│   ├── JSONExporter.swift
│   ├── ArchiveExporter.swift         # ZIP « tout »
│   └── ExportService.swift           # orchestre : format → URL temporaire → ShareLink
├── Storage/
│   ├── RoomStore.swift               # CRUD paquets .roomscan, méta, vignettes ; @Observable ; bi-plateforme
│   ├── RoomRecord.swift              # meta.json : id, name, createdAt, label, area, version
│   ├── RoomPackage.swift             # UTType fr.vincentlauriat.roomscanner.room, lecture/écriture du paquet
│   ├── StorageLocation.swift         # protocole : racine iCloud (ubiquity) ou locale ; sélection au lancement
│   └── FileLayout.swift              # chemins Rooms/ Exports/, création des dossiers, migration future
├── Sync/
│   ├── UbiquityMonitor.swift         # NSMetadataQuery sur Rooms/ : liste live, état par pièce, téléchargement à la demande
│   ├── CloudAvailability.swift       # ubiquityIdentityToken, bascule iCloud ↔ local, bannière
│   └── ConflictResolver.swift        # NSFileVersion : garde la plus récente, conserve l'autre en copie « (conflit) »
├── UI/
│   ├── RoomListView.swift
│   ├── RoomDetailView.swift          # TabView : Plan2D / 3D / Mesures + bouton Exporter
│   ├── Plan2DView.swift              # Canvas SwiftUI ou UIView Core Graphics + zoom/pan
│   ├── QuickLookView.swift           # QLPreviewController wrapper (bouton secondaire)
│   ├── MeasuresView.swift
│   ├── ExportSheet.swift             # + « Enregistrer dans iCloud Drive »
│   ├── CloudStatusBadge.swift        # état iCloud par pièce
│   ├── UnsupportedDeviceView.swift   # iOS
│   ├── CameraDeniedView.swift        # iOS
│   └── SettingsView.swift
├── MacUI/                            # cible macOS uniquement
│   ├── MacRootView.swift             # NavigationSplitView : sidebar pièces / détail
│   ├── MacMenuCommands.swift         # Fichier › Exporter… (⌘E), Imprimer (⌘P), Révéler dans le Finder
│   ├── PrintController.swift         # NSPrintOperation sur le PDF vectoriel de PlanRenderer
│   ├── DragExportProvider.swift      # NSItemProvider : glisser un export vers une autre app
│   ├── OpenWithMenu.swift            # NSWorkspace.urlsForApplications(toOpen:)
│   └── MacEmptyStateView.swift       # « Scannez avec votre iPhone… »
├── Resources/
│   ├── Localizable.xcstrings         # fr / en
│   └── Assets.xcassets               # AppIcon, couleurs sémantiques
├── Info.plist                        # iOS : NSCameraUsageDescription, UIFileSharingEnabled, NSUbiquitousContainers, UTExportedTypeDeclarations (.roomscan)
├── Info-macOS.plist                  # macOS : NSUbiquitousContainers, UTExportedTypeDeclarations, CFBundleDocumentTypes (.roomscan)
├── RoomScanner.entitlements          # iOS : iCloud Documents + conteneur iCloud.fr.vincentlauriat.roomscanner
└── RoomScannerMac.entitlements       # macOS : App Sandbox, iCloud Documents, user-selected files r/w, print, network client

RoomScannerTests/                      # même cible de tests compilée pour iOS (simulateur) et macOS
├── Fixtures/                          # CapturedRoom JSON capturés sur device + synthétiques
│   ├── rectangular_room.json
│   ├── l_shaped_room.json
│   └── room_with_openings.json
├── FloorPlanBuilderTests.swift
├── MeasurementsTests.swift
├── SVGExporterTests.swift             # golden files
├── DXFExporterTests.swift             # golden files + validation structure (paires code/valeur)
├── PlanRendererTests.swift            # rendu PNG non vide, dimensions, snapshot léger
├── PlanSceneBuilderTests.swift        # nombre d'entités, positions/dimensions des murs, texture sol présente
├── RoomStoreTests.swift               # StorageLocation locale dans un répertoire temporaire
├── RoomPackageTests.swift             # écriture/lecture d'un .roomscan, UTType
└── ConflictResolverTests.swift        # deux versions simulées → la plus récente gagne, copie « (conflit) » créée

docs/
├── index.html                          # landing page GitHub Pages (EN/FR/ZH-Hant, assets/base.css du hub)
├── assets/base.css
└── superpowers/specs/…                 # cette spec
Scripts/
└── release.sh                          # build Release Mac, Developer ID, notarisation, DMG, Sparkle sign_update, appcast.xml
appcast.xml                             # flux Sparkle (généré par release.sh, commité sur main)
project.yml                             # XcodeGen : RoomScanner (iOS 18), RoomScannerMac (macOS 15), RoomScannerTests, package Sparkle
```

### 5.3 Flux de données principal

1. `ScanView` crée un `RoomCaptureView`, lance `captureSession.run(configuration:)` avec `isCoachingEnabled = true`.
2. L'utilisateur termine → `captureView(shouldPresent:error:)` retourne `true` → RoomPlan post-traite.
3. `captureView(didPresent: CapturedRoom, error:)` → `ScanCoordinator` reçoit la pièce (ou l'erreur).
4. `RoomStore.save(capturedRoom)` : crée le paquet `<racine>/Rooms/<uuid>.roomscan/` (racine = conteneur iCloud si disponible, sinon Documents local) via `NSFileCoordinator`, écrit `room.json` (JSONEncoder), `room.usdz` (`export(to:exportOptions: .parametric)`), `meta.json`, génère `thumbnail.png` via `PlanRenderer`. iCloud propage le paquet vers le Mac.
5. `CapturedRoomAdapter.scanInput(from: capturedRoom)` (iOS) → `ScanInput` → `FloorPlanBuilder.build(from:name:)` → `FloorPlan`, écrit dans `plan.json` (et `scan.json`) du paquet pour que le Mac le lise sans RoomPlan ; `room.json` reste la source de vérité et permet de recalculer `plan.json` quand `FloorPlan.schemaVersion` change.
6. `House(rooms: [floorPlan])` → `RoomDetailView` affiche Plan2D / Viewer (3D · 2D · AR) / Mesures. `PlanSceneBuilder` construit les entités RealityKit une fois ; le changement de mode ne touche que la caméra et la visibilité des murs.
7. `ExportSheet` → `ExportService.export(room, format)` → URL dans `tmp/` → `ShareLink` (iOS : feuille de partage ; Mac : `NSSharingServicePicker`) **ou** « Enregistrer dans iCloud Drive » → copie coordonnée dans `<racine>/Exports/<Pièce>/`.
8. Sur le Mac, `UbiquityMonitor` (`NSMetadataQuery`) voit arriver le `.roomscan`, déclenche le téléchargement si besoin, et la pièce apparaît dans la barre latérale ; le détail réutilise `FloorPlanBuilder`, `PlanRenderer`, `PlanSceneBuilder` et les exporteurs à l'identique.

### 5.4 Modèle pivot `FloorPlan`

```swift
struct House: Codable, Equatable {          // D14 — v1 : une seule pièce
    var id: UUID
    var name: String
    var stories: [Story]
    var allRooms: [FloorPlan] { stories.flatMap(\.rooms) }
}
struct Story: Codable, Equatable { var index: Int; var rooms: [FloorPlan] }

struct FloorPlan: Codable, Equatable {
    var id: UUID
    var name: String
    var story: Int
    var transform: simd_float4x4        // placement dans le repère maison — identité en v1
    var walls: [Wall]                 // segments 2D + hauteur
    var openings: [Opening]           // portes, fenêtres, ouvertures rattachées à un mur
    var objects: [PlacedObject]       // meubles/équipements (boîte 2D orientée)
    var floorPolygon: [Point2D]       // contour du sol (m), issu de floors[0].polygonCorners
    var ceilingHeight: ClosedRange<Double>  // min…max (m)
    var bounds: Rect2D                // englobant pour la mise en page
}

struct Wall: Codable, Equatable {
    var id: UUID; var start: Point2D; var end: Point2D
    var height: Double; var thickness: Double  // épaisseur graphique (RoomPlan ne la mesure pas : constante 0,10 m)
    var confidence: Confidence
    var length: Double { start.distance(to: end) }
}

struct Opening: Codable, Equatable {
    enum Kind: String, Codable { case door, window, opening }
    var id: UUID; var kind: Kind; var wallID: UUID?
    var center: Point2D; var width: Double; var height: Double
    var sillHeight: Double            // hauteur d'allège (fenêtre) — 0 pour porte/ouverture
    var angle: Double                 // orientation dans le plan (rad)
    var confidence: Confidence
}

struct PlacedObject: Codable, Equatable {
    var id: UUID; var category: String   // "table", "sofa", … (rawValue localisable)
    var center: Point2D; var size: Size2D; var height: Double; var angle: Double
    var confidence: Confidence
}
```

**Projection RoomPlan → 2D** (`FloorPlanBuilder`) :
- Un `Surface` mur a `transform` (4×4) et `dimensions` = (largeur, hauteur, profondeur≈0).
  Centre = translation `(t.x, t.z)`. Direction = colonne 0 du `transform` (axe local X) projetée sur XZ, normalisée.
  `start = centre − dir × largeur/2`, `end = centre + dir × largeur/2`. Hauteur = `dimensions.y`.
- Si `polygonCorners` est non vide (mur non rectangulaire, iOS 17), la hauteur min/max vient des coins ; la trace au sol reste le segment.
- Portes/fenêtres : `parentIdentifier` → mur ; `center` = `(t.x, t.z)` ; `width = dimensions.x`, `height = dimensions.y` ; `sillHeight = (t.y − dimensions.y/2) − floorY`.
- Objets : centre `(t.x, t.z)`, `size = (dimensions.x, dimensions.z)`, `angle` = atan2 de la colonne 0 projetée.
- Sol : contour obtenu en **chaînant les murs** (extrémités raccordées à 25 cm près, robuste et indépendant des conventions de `polygonCorners`) ; à défaut (scan partiel), englobant des murs. `polygonCorners` sera confronté aux fixtures réelles en phase 2.
- Repère plan : X vers la droite, **Y_plan = −Z_room** pour obtenir une vue de dessus « naturelle » (nord arbitraire en v1).

**Mesures** (`Measurements`) :
- Surface au sol : formule du lacet (shoelace) sur `floorPolygon` ; repli : produit des dimensions.
- Périmètre : somme des longueurs de murs.
- Hauteur sous plafond : min/max des `Wall.height`.
- Toutes les valeurs stockées en **mètres** (Double), formatées en cm / m² à l'affichage et dans les exports 2D (`MeasurementFormatter`, locale système).

### 5.4 bis Scène RealityKit (`PlanSceneBuilder`, D13)
- Racine : une `Entity` par `House`, une `Entity` enfant par pièce (positionnée par `FloorPlan.transform`) → coloration et sélection par pièce en v2.
- Mur : `ModelEntity(mesh: .generateBox(width: longueur, height: hauteur, depth: 0,10))`, placé au milieu du segment, tourné de `atan2`, matériau `SimpleMaterial` blanc cassé. Ouvertures : la découpe booléenne n'existe pas dans RealityKit → un mur avec ouvertures est décomposé en **3 boîtes** (avant / linteau / après) + panneau : porte = boîte fine brun clair, fenêtre = boîte fine bleu translucide (`alpha 0,35`).
- Sol : `generatePlane` aux dimensions de l'englobant, matériau `UnlitMaterial` texturé par un PNG du plan 2D rendu par `PlanRenderer` (mode « texture » : sans cartouche, cotes incluses) via `TextureResource.load(contentsOf:)`. C'est ce qui fait le **mode 2D**.
- Objets : boîtes grises semi-transparentes + libellé (`MeshResource.generateText`) orienté vers la caméra.
- Cotes 3D (option) : texte `generateText` posé au-dessus de chaque mur.
- Modes : **3D** = murs visibles, `camera = .virtual`, `realityViewCameraControls(.orbit)` ; **2D** = murs à hauteur 0,02 m (aplatis), `PerspectiveCamera` au zénith verrouillée, contrôles `.pan` + `.dolly` ; **AR** (iOS) = `camera = .spatialTracking`, même racine, échelle 1/20, 1/50 ou 1, ancrée via `AnchorEntity(.plane(.horizontal, …))`, déplaçable au doigt, pivotable à deux doigts. Le changement de mode ne modifie que `content.camera`, la caméra virtuelle et la visibilité des murs ; les entités sont construites une fois.
- Plateformes : une seule `RealityView` SwiftUI, commune iOS/macOS ; `#if os(iOS)` uniquement pour le mode AR (`ARPlacementController`, `.spatialTracking`).
- Performance : une pièce = quelques dizaines d'entités ; une maison entière (v2) reste < 1 000 entités — largement dans le budget RealityKit.

### 5.5 Spécification des exports

**Rendu commun (`PlanRenderer`)** — utilisé par PDF, PNG, vignette, texture du sol, impression Mac et `Plan2DView`. Écrit en **Core Graphics pur** (`CGContext(consumer:mediaBox:nil)` pour le PDF, `CGContext(data:width:height:…)` pour le bitmap) afin de compiler à l'identique sur iOS et macOS — pas d'`UIGraphicsPDFRenderer` ni de `NSImage` dans le moteur :
- Échelle automatique : le plan occupe 80 % de la zone utile ; échelle arrondie aux valeurs standard (1:20, 1:25, 1:50, 1:100) et affichée dans le cartouche.
- Murs : trait épais noir (épaisseur 0,10 m à l'échelle). Portes : ouverture dans le mur + arc de 90° (`ARC`). Fenêtres : ouverture + double trait fin. Ouvertures : pointillés.
- Cotes : ligne de cote parallèle à chaque mur à 0,30 m à l'extérieur, flèches, texte en cm, orienté lisible (jamais tête en bas).
- Objets : rectangles gris clair avec libellé court (« Table », « Canapé »).
- Cartouche : nom de la pièce, date, surface m², périmètre, hauteur sous plafond, échelle, « 3D Scanner ».

| Format | Détails techniques | Ouvert par |
|---|---|---|
| **PDF** | `CGContext` PDF, A4 paysage (842×595 pt), une page ; texte vectoriel (Core Text) ; métadonnées titre/auteur | Aperçu, Adobe, impression, tout le monde |
| **PNG** | `CGContext` bitmap échelle 3× (≈2526×1785 px), fond blanc, encodage `CGImageDestination` | Messages, Photos, Word… |
| **SVG** | `viewBox` en **millimètres** (1 unité = 1 mm), `<g id="walls">`, `doors`, `windows`, `openings`, `objects`, `dimensions`, `text` ; `stroke-width` en mm ; police `sans-serif` | Illustrator, Figma, Inkscape, navigateurs |
| **DXF R12** | ASCII, sections `HEADER` (`$ACADVER`=AC1009, `$INSUNITS`=6 mètres, `$EXTMIN/$EXTMAX`), `TABLES` (calques `WALLS` 7, `DOORS` 1, `WINDOWS` 5, `OPENINGS` 8, `OBJECTS` 8, `DIMENSIONS` 3, `TEXT` 7), `ENTITIES` (`LINE`, `ARC`, `TEXT`, `POLYLINE` fermée pour le sol). Pas d'entités `DIMENSION` natives (peu portables en R12) : cotes en `LINE` + `TEXT`. | AutoCAD, LibreCAD, SketchUp, QCAD, ArchiCAD, Fusion 360 |
| **USDZ** | `CapturedRoom.export(to:exportOptions:)` — défaut `.parametric` (murs/portes/fenêtres propres), option `.mesh` (nuage brut) | Aperçu/AR iOS, Xcode, Reality Composer, Blender, Omniverse |
| **OBJ / STL / PLY** | `MDLAsset(url: usdz)` → `export(to:)`. OBJ + `.mtl` généré par Model I/O ; conversion sur file d'attente arrière-plan | Blender, SketchUp, Cinema 4D, Meshlab, impression 3D (STL) |
| **JSON** | `JSONEncoder` de `CapturedRoom` (format Apple) + `meta.json` | Support, tests, réimport futur |
| **ZIP** | Tous les formats + `README.txt` (nom, date, contenu) | Archivage, envoi unique |

### 5.6 UI — écrans et états

| Écran | Contenu | États particuliers |
|---|---|---|
| **RoomList** (racine) | Liste des pièces (vignette, nom, surface, date), bouton « + Scanner », réglages | Vide : illustration + bouton d'appel ; appareil non compatible : bannière permanente et bouton désactivé |
| **Scan** | `RoomCaptureView` plein écran, Annuler (haut gauche), Terminer (haut droit), overlay « Traitement… » | Caméra refusée → `CameraDeniedView` ; erreur RoomPlan → alerte avec message humain + « Réessayer » |
| **RoomDetail** | Titre éditable, `TabView` Plan 2D / Viewer / Mesures, bouton Exporter | Plan 2D : pinch-zoom, double-tap reset |
| **Viewer** (onglet) | `RealityView` plein onglet, segment **3D · 2D · AR** (AR masqué sur Mac), boutons cotes on/off, recentrer, échelle (AR), « Aperçu rapide » | 3D : orbite/zoom ; 2D : zénith, pan/zoom ; AR : coaching « déplacez l'iPhone », toucher pour poser, glisser/pivoter, bouton « Réinitialiser l'ancrage » ; caméra refusée → bascule automatique en 3D avec bandeau |
| **ExportSheet** | Sections 2D / 3D / Données ; chaque ligne = format + icône + description ; toucher → génération (spinner) → feuille de partage | Erreur de génération → alerte ; conversion OBJ longue → progression indéterminée |
| **Settings** | Langue (système), à propos, version, état iCloud, lien vers le dossier « 3D Scanner » (Fichiers / Finder) | iCloud inactif : explication + bouton Réglages |
| **Mac — fenêtre principale** | `NavigationSplitView` : sidebar (pièces + badge iCloud + recherche), détail = onglets Plan 2D / 3D / Mesures, barre d'outils (Exporter, Partager, Imprimer, Révéler dans le Finder) | Vide : `MacEmptyStateView` ; pièce non téléchargée : bouton « Télécharger » ; conflit : bandeau « Version en conflit conservée » |
| **Mac — Exporter** | Menu Fichier › Exporter… (sous-menu formats) ou feuille : chaque format = bouton + zone glissable + « Ouvrir avec… » + « Enregistrer dans iCloud Drive » + « Enregistrer sous… » (`NSSavePanel`) | Conversion OBJ en cours : indicateur |

Messages d'erreur RoomPlan traduits en langage humain (extrait) :
`exceedSceneSizeLimit` → « La pièce est trop grande pour un seul scan. Scannez-la en deux parties. » ;
`lowTexture` → « Surfaces trop uniformes : allumez la lumière ou approchez-vous des murs. » ;
`deviceTooHot` → « L'iPhone chauffe : laissez-le refroidir une minute. » ;
`worldTrackingFailure` → « Suivi perdu : recommencez en bougeant plus lentement. » ;
`deviceNotSupported` → écran dédié.

### 5.7 Persistance et synchronisation iCloud (D6, D16, D17)

```
<racine>/                      # iCloud : FileManager.url(forUbiquityContainerIdentifier: "iCloud.fr.vincentlauriat.roomscanner")
│                              # repli : Documents local (iOS) / conteneur sandbox (Mac)
└── Documents/                 # exposé comme « iCloud Drive / 3D Scanner » (NSUbiquitousContainerIsDocumentScopePublic)
    ├── Rooms/
    │   └── 6F9619FF-….roomscan/   # paquet (un seul « fichier » dans Fichiers / Finder)
    │       ├── room.json          # CapturedRoom encodé (source de vérité, lisible sur iOS seulement)
    │       ├── scan.json          # ScanInput neutre (lisible partout, fixtures de test)
    │       ├── plan.json          # FloorPlan (schemaVersion) — ce que le Mac et les exporteurs lisent
    │       ├── room.usdz          # export paramétrique, généré à la sauvegarde
    │       ├── meta.json          # RoomRecord { id, name, createdAt, label, areaM2, storyIndex, schemaVersion }
    │       └── thumbnail.png      # 600×400, vignette du plan 2D
    └── Exports/
        └── Salon/                 # « Enregistrer dans iCloud Drive »
            ├── Salon.pdf  Salon.dxf  Salon.svg  Salon.usdz  Salon.obj …
```
- **Sélection de la racine** (`StorageLocation`) au lancement : si `FileManager.default.ubiquityIdentityToken != nil` et que l'URL du conteneur est obtenue (appel hors main thread) → iCloud ; sinon local. Migration local → iCloud proposée quand iCloud devient disponible (déplacement coordonné des paquets).
- **Listing** : `NSMetadataQuery` (`NSMetadataQueryUbiquitousDocumentsScope`, prédicat sur `*.roomscan`) fournit la liste live, `NSMetadataUbiquitousItemDownloadingStatusKey` et `…IsUploadedKey` pour le badge d'état ; repli : énumération du dossier en local.
- **Téléchargement à la demande** : un paquet non local est affiché grisé avec sa vignette si disponible ; ouverture → `startDownloadingUbiquitousItem(at:)` + progression.
- **Lecture/écriture** toujours via `NSFileCoordinator` (les paquets sont écrits en une seule opération coordonnée pour arriver complets sur l'autre appareil).
- **Conflits** (`NSFileVersion.unresolvedConflictVersionsOfItem`) : la version la plus récente gagne, l'autre est conservée en `<nom> (conflit).roomscan` — on ne perd jamais un scan.
- `schemaVersion` dans `meta.json` pour d'éventuelles migrations.
- Les exports à la demande sont générés dans `tmp/` (non conservés) sauf « Enregistrer dans iCloud Drive ».
- iOS : `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` = `true` en plus, pour le dossier local de repli.
- **UTType** `fr.vincentlauriat.roomscanner.room` (`.roomscan`, conforme à `com.apple.package`) déclaré dans les deux `Info.plist` (`UTExportedTypeDeclarations`) ; Mac : `CFBundleDocumentTypes` → double-clic ouvre l'app ; iOS : `.onOpenURL` → import.

### 5.8 Gestion des erreurs

- Toutes les erreurs métier passent par `enum AppError: LocalizedError` (`unsupportedDevice`, `cameraDenied`, `scanFailed(RoomPlan.Error)`, `exportFailed(format, underlying)`, `storageFailed`, `cloudUnavailable`, `downloadFailed`, `conflictResolved(kept:)`).
- Les erreurs d'export ne perdent jamais le scan : le `room.json` est écrit **avant** toute conversion.
- La conversion Model I/O tourne hors main thread (`Task.detached`), avec timeout doux (30 s) et message si dépassé.
- Aucune suppression de logs/warnings pour masquer un problème : chaque erreur affichée a une cause identifiée.

---

## 6. Tests et vérification

### 6.1 Automatisés (cible `RoomScannerTests`, exécutables sur simulateur)
- **FloorPlanBuilder** : à partir de fixtures JSON (`CapturedRoom` réels capturés sur l'iPhone de Vincent + pièces synthétiques construites en code), vérifier nombre de murs, longueurs à ±1 cm, rattachement des portes au bon mur, surface au sol.
- **Measurements** : shoelace sur carré 4×3 = 12 m² ; pièce en L ; périmètre ; hauteurs min/max.
- **SVGExporter / DXFExporter** : comparaison à des golden files ; vérification structurelle DXF (paires code/valeur, `0/EOF` final, calques déclarés = calques utilisés). Validation externe optionnelle ponctuelle avec `ezdxf` (Python) pour prouver l'ouverture dans un lecteur indépendant — hors CI, pas de dépendance ajoutée au projet.
- **PlanRenderer** : PNG non vide, dimensions attendues, pixels noirs présents (murs dessinés).
- **PlanSceneBuilder** : sur fixture, nombre d'entités murs = nombre de murs (+ découpes), position/rotation/dimensions des boîtes à ±1 mm, présence de la texture sol ; s'exécute sur simulateur (RealityKit hors AR fonctionne en simulateur).
- **RoomStore / RoomPackage** : cycle save/list/delete dans un `StorageLocation` local temporaire ; `meta.json` cohérent ; paquet `.roomscan` relu à l'identique ; `UTType` reconnu.
- **ConflictResolver** : deux versions simulées (`NSFileVersion` mocké derrière un protocole) → la plus récente gagne, copie « (conflit) » créée.
- **Bi-plateforme** : la cible de tests s'exécute **sur simulateur iOS et sur macOS** (même sources) — garantit que Domain/Export/Viewer/Storage compilent et se comportent pareil des deux côtés.

### 6.2 Sur appareil (checklist manuelle, dans `TODOS.md` à chaque jalon)
- Scan complet d'une pièce rectangulaire (chambre) : cotes cohérentes avec un mètre ruban (écart attendu < 2 %).
- Pièce avec 2 portes + 1 fenêtre : ouvertures au bon endroit sur le plan.
- Export de chaque format → ouverture dans : Aperçu Mac (PDF, SVG, USDZ), LibreCAD ou QCAD (DXF), Blender (OBJ, USDZ), Fichiers iOS (ZIP).
- Viewer : orbite fluide (60 fps) ; mode 2D lisible ; AR : maquette posée sur une table à 1:50, superposition 1:1 dans la pièce scannée avec écart visuel < 10 cm après alignement manuel.
- Refus caméra, appareil sans LiDAR (iPhone non-Pro d'un proche ou simulateur → écran non compatible).
- **iCloud** : scan sur iPhone → la pièce apparaît sur le Mac en < 1 min ; renommage sur Mac → visible sur iPhone ; iPhone en mode avion → repli local, puis fusion au retour du réseau ; « Enregistrer dans iCloud Drive » → fichier visible dans Finder et dans Fichiers ; `.roomscan` en AirDrop → import.
- **Mac** : double-clic sur un `.roomscan` dans le Finder ouvre l'app ; ⌘P imprime le plan ; glisser le PDF sur Aperçu et le DXF sur LibreCAD ; « Ouvrir avec… » liste les apps installées.

### 6.3 Commandes de build
```bash
xcodegen generate
# Simulateur (compile tout sauf l'exécution RoomPlan) + tests
xcodebuild -scheme RoomScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build test
# Device / capacités : la première fois, crée l'App ID, le conteneur iCloud et les profils
xcodebuild -scheme RoomScanner -destination 'generic/platform=iOS' -allowProvisioningUpdates build
# macOS (compile + tests de la même base de code côté Mac)
xcodebuild -scheme RoomScannerMac -destination 'platform=macOS' build test
# Device (Vincent lance depuis Xcode : ⌘R sur son iPhone, signature automatique équipe KFLACS69T9)
# Release Mac : Scripts/release.sh → DMG signé Developer ID + notarisé (skill macos-app-release)
```

---

## 7. Étapes de réalisation

| Phase | Contenu | Vérification de sortie |
|---|---|---|
| **0 — Bootstrap** | Dépôt GitHub public + `main` ; `project.yml` **deux cibles** (`RoomScanner` iOS 18, `RoomScannerMac` macOS 15, package Sparkle côté Mac) + cible de tests bi-plateforme, arborescence, `Info.plist` / `Info-macOS.plist` (`NSCameraUsageDescription`, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `UIRequiredDeviceCapabilities: arkit`, `NSUbiquitousContainers`, `UTExportedTypeDeclarations`, clés `SU*` Sparkle), entitlements iCloud + sandbox Mac, `Localizable.xcstrings`, **landing page `docs/index.html`** + GitHub Pages activé, ligne dans le hub et le profil GitHub | `xcodebuild build test` passe sur simulateur iOS **et** sur macOS (apps vides) ; `-allowProvisioningUpdates` a créé App ID + conteneur iCloud ; landing page en ligne |
| **1 — Domaine** (TDD) | `Geometry`, `FloorPlan`, `House`, `FloorPlanBuilder`, `Measurements`, `RoomNaming` + fixtures synthétiques | Tests verts sur les deux plateformes ; longueurs/surfaces exactes |
| **2 — Stockage local + Scan iOS** | `StorageLocation` (local), `RoomPackage` (.roomscan), `RoomStore`, `RoomRecord` ; `RoomCaptureViewRepresentable`, `ScanView`, `ScanCoordinator` (propriétaire de l'`ARSession`), compat/caméra | Sur iPhone : scan → paquet `.roomscan` écrit ; **capture des premières fixtures réelles** ; tests `RoomStore`/`RoomPackage` verts |
| **3 — Rendu 2D + Mesures** | `PlanRenderer` Core Graphics pur (modes page et texture), `Plan2DView`, `MeasuresView`, `RoomDetailView`, vignettes | Plan coté lisible sur iPhone **et** dans la fenêtre Mac (vue minimale) ; PNG de test non vide sur les deux plateformes |
| **4 — Visualiseur RealityKit** | `PlanSceneBuilder`, `ViewerView` (`RealityView` commune), `ViewerMode` (3D / 2D zénith), `ARPlacementController` (iOS, `.spatialTracking`, 1:20/1:50/1:1), `ViewerControls`, `QuickLookView` | Tests `PlanSceneBuilder` verts ; iPhone : orbite, 2D, maquette AR ; Mac : orbite souris/trackpad, 2D |
| **5 — Exports 2D** | `PDFExporter`, `PNGExporter`, `SVGExporter`, `DXFExporter`, `ExportSheet`, `ShareLink` (iOS + Mac) | Golden tests verts ; DXF ouvert dans LibreCAD/QCAD ; SVG dans Figma/Inkscape ; PDF dans Aperçu |
| **6 — Exports 3D** | `USDZExporter` (options), `ModelIOConverter` (OBJ/STL/PLY) | OBJ ouvert dans Blender ; USDZ en AR sur iPhone ; conversions identiques sur Mac |
| **7 — iCloud Drive** | `StorageLocation` iCloud, `CloudAvailability` (bascule + migration), `UbiquityMonitor` (`NSMetadataQuery`, téléchargement), `ConflictResolver`, `CloudStatusBadge`, « Enregistrer dans iCloud Drive », import `.roomscan` (`onOpenURL`) | Scan iPhone → pièce visible sur Mac < 1 min ; dossier « 3D Scanner » dans Fichiers et Finder ; mode avion → repli local puis fusion ; tests `ConflictResolver` verts |
| **8 — App Mac** | `MacRootView` (split view), `MacMenuCommands` (⌘E, ⌘P, Révéler), `PrintController`, `DragExportProvider`, `OpenWithMenu`, `MacEmptyStateView`, `CFBundleDocumentTypes` | Double-clic `.roomscan` ouvre l'app ; ⌘P imprime ; glisser PDF → Aperçu, DXF → LibreCAD ; « Ouvrir avec… » liste les apps |
| **9 — Bibliothèque & finition** | `RoomListView` complet, suppression, renommage (sync), `JSONExporter`, `ArchiveExporter` (ZIP « tout »), réglages (état iCloud), icônes iOS/Mac, localisation complète, **intégration Sparkle** (menu « Rechercher les mises à jour… », `SUFeedURL`, `SUPublicEDKey`) | Checklist §6.2 entièrement cochée sur iPhone et Mac |
| **10 — Release 1.0.0** | Version 1.0.0 ; iOS : installation Xcode / TestFlight ; Mac : génération **unique** de la clé EdDSA Sparkle (compte trousseau `RoomScanner`, sauvegarde), `Scripts/release.sh` → DMG Developer ID notarisé dans `release/`, `sign_update`, `appcast.xml` ; notes de release ; tag `v1.0.0` et GitHub Release **après confirmation de Vincent** ; landing page et hub mis à jour (lien DMG) | `spctl -a -t exec -vv` accepté, `stapler validate` OK ; Sparkle détecte la mise à jour depuis une build antérieure ; installé sur l'iPhone et le Mac de Vincent ; `README.md` à jour |
| **v2 — Maison entière** | Mode « Scanner la maison » (ARSession partagée), `StructureBuilder`, `House` multi-pièces/étages, viewer maison (iPhone + Mac), exports maison, glTF | Spec v2 dédiée à rédiger après la v1 |

Chaque phase = une branche `feat/phase-N-<nom>` → PR → merge sur `main` ; jamais de push direct sur `main` ; les phases s'enchaînent **sans validation intermédiaire** (décision Vincent), seuls les tags/releases sont confirmés.
Chaque phase se termine par une mise à jour de `CHANGES.md`, `TODOS.md`, `MEMORY.md`.

---

## 8. Risques et points ouverts

| Risque | Impact | Mitigation |
|---|---|---|
| Model I/O sur iOS ne convertit pas l'USDZ RoomPlan aussi bien que sur macOS (vérifié uniquement sur Mac) | OBJ absent ou vide | Spike de 10 min sur device en phase 6 ; repli : génération OBJ maison depuis la géométrie paramétrique (murs = boîtes) — simple |
| Précision RoomPlan (±2–5 cm typiques, pire sur murs vitrés/miroirs) | Cotes contestables | Afficher la confiance, préciser dans le cartouche « mesures indicatives — RoomPlan » ; v2 : ajustement manuel |
| Pièce trop grande (> ~ 9 m × 9 m) ou en L complexe | Échec de scan | Message explicite ; v2 multi-scans + `StructureBuilder` |
| Épaisseur des murs non mesurée par RoomPlan | Plan « fil de fer » | Épaisseur graphique constante 10 cm, documentée dans le cartouche |
| Fichiers DXF : variabilité des lecteurs | Ouverture ratée dans un logiciel | R12 minimal = le plus portable ; tests d'ouverture sur 2 lecteurs libres avant release |
| Xcode 27 / iOS 27 beta | Instabilités SDK | Deployment target 17 ; pas d'API 27-only |
| `ARView.nonAR` n'a pas de caméra orbite intégrée | Viewer 3D à écrire | `OrbitCameraController` maison : `PerspectiveCamera` sur une sphère (yaw/pitch/distance) pilotée par `UIPanGestureRecognizer` / pinch — ~150 lignes, bien connu |
| Pas de découpe booléenne dans RealityKit | Portes/fenêtres « collées » sur le mur | Décomposition du mur en 3 boîtes autour de chaque ouverture (§5.4 bis) |
| Alignement AR 1:1 imprécis (le repère du scan n'est pas celui de la session AR de visualisation) | Superposition décalée | Alignement manuel (glisser/pivoter) en v1 ; v2 : relocalisation via `ARWorldMap` sauvegardée au moment du scan |
| iCloud Drive + app Mac signée **Developer ID** (hors App Store) : l'entitlement iCloud exige un **profil de provisionnement Developer ID** embarqué | Pas de sync sur le Mac distribué en DMG | Déjà résolu sur TheNews (même équipe, `-Release.entitlements` dédié) : reprendre le même mécanisme dans `release.sh` ; en développement, Xcode (⌘R) gère tout |
| Sparkle 2 dans une app **sandboxée** : l'installateur passe par un XPC (`SUEnableInstallerLauncherService`) et des exceptions `mach-lookup` | Mise à jour qui échoue silencieusement | Suivre la doc Sparkle « Sandboxing » ; tester une vraie mise à jour 1.0.0 → 1.0.1 avant d'annoncer ; TheNews sert de référence |
| `RealityView` iOS 18 / macOS 15 : API récente, moins de retours d'expérience qu'`ARView` | Comportements inattendus (AR passthrough, gestes) | Vérifications SDK faites ; `PlanSceneBuilder` est indépendant de la vue ; repli possible sur `ARView` wrappé sans toucher au reste |
| Latence / indisponibilité iCloud, paquet partiellement téléchargé | Pièce illisible ou fantôme | Écriture du paquet en une opération coordonnée ; badge d'état ; lecture uniquement quand `downloadingStatus == current` ; repli local |
| Conflits de renommage simultané iPhone/Mac | Deux versions | `ConflictResolver` : la plus récente gagne, l'autre conservée « (conflit) » — jamais de perte |
| Sandbox macOS + iCloud : accès aux fichiers hors conteneur | « Enregistrer sous… » refusé | `NSSavePanel` (user-selected r/w) et glisser-déposer via `NSItemProvider` : les deux passent la sandbox |
| `ARView` macOS : gestes différents (souris, trackpad, molette) | Orbite maladroite | `OrbitCameraController` reçoit des deltas abstraits ; adaptateurs `UIGestureRecognizer` (iOS) / `NSGestureRecognizer` + `scrollWheel` (Mac) |
| Multi-pièces v2 : dérive entre scans, murs communs dupliqués | Plan maison incohérent | Un seul `ARSession` pour toute la maison (déjà prévu dans `ScanCoordinator`), `StructureBuilder` gère la fusion ; tolérance de fusion des murs colinéaires dans `House` |

**Décisions de Vincent (2026-09-05)** : iOS 18 / macOS 15 minimum pour `RealityView` ; D12 validé (conteneur créé automatiquement si possible, sinon geste manuel) ; DMG Developer ID **+ Sparkle** ; tout en v1 (ZIP, A4 paysage) ; dépôt public, une branche par phase sans re-demander, landing page + hub + profil GitHub.

---

## 9. Informations pratiques

- **iCloud** : conteneur `iCloud.fr.vincentlauriat.roomscanner`, créé automatiquement au premier `xcodebuild … -allowProvisioningUpdates` (signature automatique ; repli : developer.apple.com → Identifiers → iCloud Containers) ; `Info.plist` des deux cibles : `NSUbiquitousContainers → iCloud.fr.vincentlauriat.roomscanner → { NSUbiquitousContainerIsDocumentScopePublic: true, NSUbiquitousContainerName: "3D Scanner", NSUbiquitousContainerSupportedFolderLevels: Any }`. ⚠️ Le nom public du conteneur ne se change plus une fois publié.
- **Entitlements iOS** : `com.apple.developer.icloud-services = [CloudDocuments]`, `com.apple.developer.icloud-container-identifiers = [iCloud.fr.vincentlauriat.roomscanner]`, `com.apple.developer.ubiquity-container-identifiers = [iCloud.fr.vincentlauriat.roomscanner]`.
- **Entitlements macOS** : les trois ci-dessus + `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.print`, `com.apple.security.network.client`, exceptions Sparkle `com.apple.security.temporary-exception.mach-lookup.global-name` = [`$(PRODUCT_BUNDLE_IDENTIFIER)-spks`, `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`] ; un `RoomScannerMac-Release.entitlements` ajoute `com.apple.developer.icloud-container-environment = Production` pour le DMG.
- **Sparkle (Info-macOS.plist)** : `SUFeedURL = https://raw.githubusercontent.com/vincentlauriat/3DScanner/main/appcast.xml`, `SUPublicEDKey` (générée en phase 10, jamais changée), `SUEnableAutomaticChecks = true`, `SUScheduledCheckInterval = 86400`, `SUEnableInstallerLauncherService = true`.
- **Landing page** : `docs/index.html` + `docs/assets/base.css` (copie du hub), GitHub Pages source `main:/docs` → `https://vincentlauriat.github.io/3DScanner/` ; ligne `B-15` dans `vincentlauriat.github.io/index.html` ; entrée dans `vincentlauriat/vincentlauriat/README.md`.
- **Permissions Info.plist iOS** : `NSCameraUsageDescription` (« Le scan LiDAR de la pièce utilise la caméra. »), `UIRequiredDeviceCapabilities` = `[arkit]`, `UIFileSharingEnabled` = YES, `LSSupportsOpeningDocumentsInPlace` = YES.
- **Type déclaré** : `fr.vincentlauriat.roomscanner.room` (`.roomscan`, conforme à `com.apple.package`), `UTExportedTypeDeclarations` sur les deux cibles, `CFBundleDocumentTypes` sur Mac.
- **Types de fichiers exportés (UTType)** : `.pdf`, `.png`, `.svg`, `public.dxf` (déclaré via `UTType(importedAs:)` si absent), `.usdz`, `public.geometry-definition-format` (OBJ), `public.standard-tesselated-geometry-format` (STL), `.json`, `.zip`.
- **Signature** : automatique, équipe `KFLACS69T9`, Apple ID de Vincent dans Xcode. Distribution iOS : installation directe depuis Xcode (usage personnel) ; TestFlight si partage. Distribution Mac : `Scripts/release.sh` (Developer ID `Vincent LAURIAT (KFLACS69T9)`, profil notarytool `AppliMacVincentGithub`, DMG dans `release/`) — voir le risque iCloud/Developer ID en §8.
- **Frameworks** : RoomPlan (iOS), ARKit (iOS), RealityKit, Model I/O, QuickLook, Core Graphics / Core Text, SwiftUI, UniformTypeIdentifiers, Foundation (iCloud ubiquity), AppKit (Mac : impression, `NSWorkspace`, `NSSavePanel`) — tous Apple, aucun SPM.
- **Repos** : local `~/DevApps/3DTools/3DScanner` (ou miroir `~/Documents/GitHub`) ; distant **public** `github.com/vincentlauriat/3DScanner` ; branche par défaut `main`, feature branches `feat/phase-N-<nom>`, PR mergées sans validation intermédiaire.
- **Docs projet** (règle DevApps) : `README.md`, `ARCHITECTURE_EN.md` + `ARCHITECTURE.md`, `PLAN.md`, `TODOS.md`, `MEMORY.md`, `CHANGES.md`, `COMMANDS.md`.

## 10. Glossaire

- **LiDAR** : capteur de profondeur laser de l'iPhone Pro, base du scan.
- **RoomPlan** : framework Apple qui transforme un scan LiDAR en pièce paramétrique (murs, portes…).
- **CapturedRoom** : structure Apple résultat d'un scan.
- **FloorPlan** : notre modèle pivot 2D/3D indépendant d'Apple.
- **USDZ** : format 3D Apple/Pixar (archive USD), ouvert en AR sur iPhone.
- **DXF R12** : format d'échange CAO texte, version 12 d'AutoCAD, le plus universellement lu.
- **Cote** : ligne de mesure annotée sur un plan.
- **Allège** : hauteur entre le sol et le bas d'une fenêtre.
- **RealityKit / ARView** : moteur 3D d'Apple ; `ARView` affiche une scène soit en 3D classique (`.nonAR`), soit en réalité augmentée (`.ar`).
- **Maquette AR** : le modèle de la pièce/maison posé à échelle réduite sur une surface réelle (table).
- **House / Story** : agrégat maison / niveau, contenant N `FloorPlan` — une seule pièce en v1.
- **Conteneur ubiquitaire** : dossier iCloud Drive privé à l'app, rendu visible sous « iCloud Drive / 3D Scanner » dans Fichiers et le Finder.
- **`.roomscan`** : paquet (dossier vu comme un fichier) contenant un scan complet ; s'ouvre dans l'app par double-clic ou AirDrop.
- **Paquet (package)** : dossier que macOS/iOS présentent comme un seul fichier (comme `.app` ou `.pages`).
