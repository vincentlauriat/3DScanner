#!/usr/bin/env bash
# Build Release 3DScanner.app (cible RoomScannerMac), signature Developer ID + Hardened
# Runtime avec les entitlements iCloud de production, notarisation, agrafage, DMG dans
# release/, signature Sparkle EdDSA et écriture de appcast.xml.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ CLÉ SPARKLE — NE JAMAIS RÉGÉNÉRER                                          │
# │ Clé privée EdDSA dans le trousseau de connexion, compte « RoomScanner »    │
# │ (utilisée par sign_update). Publique = SUPublicEDKey dans project.yml :    │
# │     qSGDP0w1B/HVt1++Bxip35K+OUI6NUvJUSxmfY9rbhE=                           │
# │ Sauvegarde : ~/.sparkle-keys/RoomScanner-EdDSA-private-key.txt             │
# │ Régénérer la clé ou changer SUPublicEDKey casse l'auto-update de tous les  │
# │ utilisateurs déjà installés.                                               │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage : ./Scripts/release.sh <version>            ex. ./Scripts/release.sh 1.0.0
#
# Prérequis (une fois) :
#   - Certificat « Developer ID Application: Vincent LAURIAT (KFLACS69T9) » dans le trousseau.
#   - Profil notarytool « AppliMacVincentGithub » :
#       xcrun notarytool store-credentials "AppliMacVincentGithub" --apple-id "vincent@lauriat.fr" --team-id "KFLACS69T9"
#   - iCloud en distribution Developer ID exige un **profil de provisionnement Developer ID**
#     (App ID fr.vincentlauriat.roomscanner + iCloud) téléchargé depuis developer.apple.com :
#       PROVISIONING_PROFILE=~/Downloads/RoomScanner_DeveloperID.provisionprofile ./Scripts/release.sh 1.0.0
#     Sans profil, la signature réussit mais iCloud Drive est refusé au lancement (l'app reste en local).
#
# Variables : SIGNING_IDENTITY, NOTARY_PROFILE, PROVISIONING_PROFILE, SKIP_NOTARIZE=1 et SKIP_DMG_LAYOUT=1 (essai local).
# Ne pousse rien sur GitHub : affiche les commandes `gh release create` / commit appcast à lancer
# après confirmation.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (ex. 1.0.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="3DScanner"
SCHEME="RoomScannerMac"
ENTITLEMENTS="$ROOT/RoomScanner/RoomScanner-macOS-Release.entitlements"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"
SPARKLE_ACCOUNT="RoomScanner"

# 1. Version
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml; then
  echo "✗ MARKETING_VERSION de project.yml ≠ $VERSION :" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  exit 1
fi
[ -f "$ROOT/release/release-notes-$VERSION.md" ] || { echo "✗ release/release-notes-$VERSION.md manquant" >&2; exit 1; }

# 1b. Sparkle compare CFBundleVersion (<sparkle:version>), pas la version marketing :
# un build number non incrémenté = mise à jour jamais proposée, sans erreur visible.
BUILD_NUMBER_YML=$(python3 -c 'import re,sys; m=re.search(r"CURRENT_PROJECT_VERSION:\s*\"?([0-9]+)\"?", open("project.yml").read()); print(m.group(1) if m else "")')
[ -n "$BUILD_NUMBER_YML" ] || { echo "✗ CURRENT_PROJECT_VERSION illisible dans project.yml" >&2; exit 1; }
if [ -f "$ROOT/appcast.xml" ]; then
  PREV_BUILD=$(python3 -c 'import re; s=open("appcast.xml").read(); v=[int(x) for x in re.findall(r"<sparkle:version>(\d+)</sparkle:version>", s)]; print(max(v) if v else 0)')
  if [ "$BUILD_NUMBER_YML" -le "$PREV_BUILD" ]; then
    echo "✗ CURRENT_PROJECT_VERSION=$BUILD_NUMBER_YML ≤ build $PREV_BUILD déjà publié dans appcast.xml." >&2
    echo "  Sparkle ne proposerait aucune mise à jour. Incrémenter CURRENT_PROJECT_VERSION dans project.yml." >&2
    exit 1
  fi
fi

# 2. Projet + build Release (signature manuelle ensuite, cf. xattrs com.apple.provenance)
command -v xcodegen >/dev/null || { echo "✗ xcodegen manquant (brew install xcodegen)" >&2; exit 1; }
echo "→ xcodegen generate"; xcodegen generate >/dev/null
echo "→ xcodebuild Release ($SCHEME)"
xcodebuild -project RoomScanner.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
APP="$ROOT/build/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ $APP absent" >&2; exit 1; }

# 3. Staging propre + profil de provisionnement
STAGING_DIR="$(mktemp -d)"; STAGING="$STAGING_DIR/$APP_NAME.app"
echo "→ Staging $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  echo "→ Profil de provisionnement embarqué"
  cp "$PROVISIONING_PROFILE" "$STAGING/Contents/embedded.provisionprofile"
else
  echo "⚠︎ Pas de PROVISIONING_PROFILE : iCloud Drive sera indisponible dans ce build (repli local)."
fi

codesign_ts() { # signature avec horodatage, 5 essais (timestamp.apple.com est capricieux)
  local target="$1"; shift
  for attempt in 1 2 3 4 5; do
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$@" "$target" && return 0
    [ "$attempt" -lt 5 ] && { echo "  ↻ codesign a échoué ($attempt/5), nouvel essai dans 5 s…"; sleep 5; }
  done
  echo "✗ codesign $target a échoué" >&2; return 1
}

echo "→ Signature de Sparkle.framework (du plus imbriqué vers l'extérieur)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"; SPARKLE_VER="$SPARKLE_FW/Versions/B"
codesign_ts "$SPARKLE_VER/Autoupdate"
codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc"
codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc"
codesign_ts "$SPARKLE_VER/Updater.app"
codesign_ts "$SPARKLE_FW"
echo "→ Signature de l'app (Developer ID, Hardened Runtime, entitlements iCloud Production)"
# codesign ne développe pas $(PRODUCT_BUNDLE_IDENTIFIER) (Xcode le fait au build) : on substitue
# la valeur dans une copie temporaire, sinon l'exception mach-lookup Sparkle serait littérale.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
RESOLVED_ENTITLEMENTS="$STAGING_DIR/entitlements.plist"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" "$ENTITLEMENTS" > "$RESOLVED_ENTITLEMENTS"
grep -q '\$(' "$RESOLVED_ENTITLEMENTS" && { echo "✗ variable non substituée dans les entitlements" >&2; exit 1; }
# Xcode injecte `application-identifier` et `team-identifier` quand il signe avec un profil ;
# `codesign` en ligne de commande ne le fait pas. Sans elles, le système ne relie pas l'app au
# profil embarqué : l'entitlement iCloud n'est pas honoré, `url(forUbiquityContainerIdentifier:)`
# renvoie nil et l'app se replie silencieusement sur le stockage local (bibliothèque vide).
# Les valeurs sont lues DANS le profil pour ne jamais diverger de lui.
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  security cms -D -i "$PROVISIONING_PROFILE" > "$STAGING_DIR/profile.plist" 2>/dev/null
  APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$STAGING_DIR/profile.plist" 2>/dev/null || true)
  TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$STAGING_DIR/profile.plist" 2>/dev/null || true)
  [ -n "$APP_ID" ] && [ -n "$TEAM_ID" ] || { echo "✗ application-identifier / team-identifier illisibles dans le profil" >&2; exit 1; }
  [ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] || { echo "✗ le profil vise $APP_ID, l'app est $BUNDLE_ID" >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$RESOLVED_ENTITLEMENTS" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$RESOLVED_ENTITLEMENTS" >/dev/null
  echo "→ application-identifier $APP_ID injecté depuis le profil"
fi
codesign_ts "$STAGING" --entitlements "$RESOLVED_ENTITLEMENTS"
SIGNED_ENT=$(codesign -d --entitlements - "$STAGING" 2>/dev/null)
echo "$SIGNED_ENT" | grep -q "$BUNDLE_ID-spks" || { echo "✗ exception mach-lookup Sparkle absente de la signature" >&2; exit 1; }
echo "$SIGNED_ENT" | grep -q "$BUNDLE_ID-spki" || { echo "✗ exception mach-lookup Sparkle (installateur) absente de la signature" >&2; exit 1; }
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  echo "$SIGNED_ENT" | grep -q "com.apple.application-identifier" || { echo "✗ application-identifier absent de la signature : iCloud sera refusé au lancement" >&2; exit 1; }
fi
codesign --verify --strict --deep "$STAGING"

# 4. DMG avec mise en page Finder
RELEASE_DIR="$ROOT/release"; mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"; rm -f "$DMG"
DMG_VOLNAME="3D Scanner $VERSION"
LAYOUT="$STAGING_DIR/dmg-layout"; mkdir -p "$LAYOUT/.background"
ditto --norsrc --noextattr --noacl "$STAGING" "$LAYOUT/$APP_NAME.app"
ln -s /Applications "$LAYOUT/Applications"
"$ROOT/Scripts/make-dmg-background.swift" "$LAYOUT/.background/background.png" >/dev/null
RW_DMG="$STAGING_DIR/temp.dmg"
hdiutil create -volname "$DMG_VOLNAME" -srcfolder "$LAYOUT" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null
DMG_MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW_DMG" | awk -F '\t' 'END {print $NF}')
echo "→ Mise en page Finder ($DMG_MOUNT)"
if [ "${SKIP_DMG_LAYOUT:-0}" = "1" ]; then echo "⚠︎ SKIP_DMG_LAYOUT=1 : mise en page Finder ignorée."; else
osascript <<APPLESCRIPT || echo "⚠︎ Mise en page Finder ignorée (session sans Finder ?)"
tell application "Finder"
    tell disk "$DMG_VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 100, 740, 480}
        set view_options to the icon view options of container window
        set arrangement of view_options to not arranged
        set icon size of view_options to 128
        set background picture of view_options to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
fi
sync; hdiutil detach "$DMG_MOUNT" -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -rf "$STAGING_DIR"

# 5. Notarisation + agrafage
NOTARIZED=0
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "⚠︎ SKIP_NOTARIZE=1 : DMG non notarisé (essai local uniquement) — appcast.xml NE sera PAS écrit."
else
  NOTARIZED=1
  echo "→ Notarisation (2–5 min)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"; xcrun stapler validate "$DMG"
fi

# 6. Signature Sparkle + appcast.xml
SPARKLE_BIN="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/RoomScanner-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1 || true)"
if [ -z "$SPARKLE_BIN" ] || [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  SPARKLE_VERSION="2.9.1"; SPARKLE_BIN="$ROOT/.sparkle-tools/bin"
  if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "→ Téléchargement des outils Sparkle $SPARKLE_VERSION"; mkdir -p "$ROOT/.sparkle-tools"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$ROOT/.sparkle-tools"
  fi
fi
echo "→ Signature Sparkle du DMG"
# Clé privée : compte trousseau « RoomScanner ». Hors session interactive (écran verrouillé, SSH),
# le trousseau refuse l'accès (-25320) : on utilise alors la sauvegarde exportée de la MÊME clé.
SPARKLE_KEY_BACKUP="$HOME/.sparkle-keys/RoomScanner-EdDSA-private-key.txt"
if ! SIG_LINE=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$DMG" 2>/dev/null); then
  [ -r "$SPARKLE_KEY_BACKUP" ] || { echo "✗ Clé Sparkle inaccessible (trousseau verrouillé) et sauvegarde $SPARKLE_KEY_BACKUP absente" >&2; exit 1; }
  echo "  ↻ trousseau inaccessible, signature avec la sauvegarde de la clé"
  SIG_LINE=$("$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_BACKUP" "$DMG")
fi
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
PUB_DATE=$(date -R)
if [ "$NOTARIZED" != "1" ]; then
  echo ""
  echo "✅ Essai local : $DMG ($(ls -lh "$DMG" | awk '{print $5}')), signature Sparkle : $SIG_LINE"
  echo "   (pas d'appcast : un appcast pointant vers une release inexistante casserait l'auto-update)"
  exit 0
fi
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>3D Scanner</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/3DScanner/main/appcast.xml</link>
    <description>3D Scanner for Mac release feed</description>
    <language>en</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/3DScanner/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/3DScanner/releases/download/v$VERSION/$APP_NAME-$VERSION.dmg"
        type="application/octet-stream"
        $SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

echo ""
echo "✅ $DMG ($(ls -lh "$DMG" | awk '{print $5}')) — appcast.xml écrit pour v$VERSION (build $BUILD_NUMBER)"
echo "Vérifications indépendantes :"
echo "  spctl -a -t open --context context:primary-signature -vv \"$DMG\""
echo "  xcrun stapler validate \"$DMG\""
echo "Publication (après confirmation de Vincent) :"
echo "  gh release create v$VERSION \"$DMG\" --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  git add appcast.xml && git commit -m 'chore: appcast for v$VERSION' && git push   # via PR, jamais direct sur main"
