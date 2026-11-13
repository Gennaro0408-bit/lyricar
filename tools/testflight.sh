#!/bin/sh
# Prepara e carica Lyricar su TestFlight (serve l'Apple Developer Program a pagamento).
# La build NON contiene un Client ID Spotify: ogni tester inserisce il proprio al primo avvio.
#
# Uso:
#   sh tools/testflight.sh archive   # compila soltanto l'archivio (nessuna modifica all'account)
#   sh tools/testflight.sh export    # crea anche l'.ipa firmata per l'App Store, senza caricarla
#   sh tools/testflight.sh upload    # crea e CARICA la build su App Store Connect
#
# Team e Bundle ID vengono letti da Config/Local.xcconfig; si possono sovrascrivere con
# le variabili TEAM_ID e BUNDLE_ID. Prima del primo upload crea l'app su App Store Connect
# con lo stesso Bundle ID (vedi docs/GUIDE.md → TestFlight).
set -e
cd "$(dirname "$0")/.."

MODE="${1:-archive}"
case "$MODE" in archive|export|upload) ;; *) echo "Uso: sh tools/testflight.sh [archive|export|upload]"; exit 1 ;; esac

conf() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*/\1/p" Config/Local.xcconfig 2>/dev/null | tail -1; }
TEAM_ID="${TEAM_ID:-$(conf DEVELOPMENT_TEAM)}"
BUNDLE_ID="${BUNDLE_ID:-$(conf APP_BUNDLE_ID)}"
[ -n "$TEAM_ID" ] && [ -n "$BUNDLE_ID" ] || { echo "Imposta DEVELOPMENT_TEAM e APP_BUNDLE_ID in Config/Local.xcconfig"; exit 1; }

BUILD_NUMBER="$(date +%Y%m%d%H%M)"   # deve crescere a ogni caricamento
OUT="build/testflight"
ARCHIVE="$OUT/Lyricar.xcarchive"
mkdir -p "$OUT"

echo "▶︎ Archivio: bundle $BUNDLE_ID, team $TEAM_ID, build $BUILD_NUMBER"
xcodebuild archive -project Lyricar.xcodeproj -scheme Lyricar -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" APP_BUNDLE_ID="$BUNDLE_ID" SPOTIFY_CLIENT_ID= CALLBACK_SCHEME=lyricar \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -quiet
echo "✓ $ARCHIVE"
[ "$MODE" = archive ] && exit 0

DEST=export; [ "$MODE" = upload ] && DEST=upload
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates -quiet
if [ "$MODE" = upload ]; then
  echo "✓ Caricata su App Store Connect (build $BUILD_NUMBER). Tra 5–30 minuti la trovi in TestFlight."
else
  echo "✓ $OUT/export/Lyricar.ipa (firmata per l'App Store, non caricata)"
fi
