#!/bin/sh
# Crea build/Lyricar.ipa: un'app NON firmata per AltStore, SideStore, Sideloadly e simili,
# che la firmano con l'Apple ID di chi la installa.
# Non contiene dati personali: Client ID vuoto (l'app lo chiede al primo avvio) e Bundle ID generico.
#
# Uso:  sh tools/build-ipa.sh
set -e
cd "$(dirname "$0")/.."

BUNDLE_ID="io.github.lyricar.app"
ROOT="$(pwd)"
OUT="$ROOT/build/ipa"
rm -rf "$OUT" build/Lyricar.ipa && mkdir -p "$OUT"

# Compila una copia in una cartella temporanea neutra: niente Config/Local.xcconfig
# e nessun percorso personale (es. /Users/<nome>) incorporato nell'eseguibile
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rsync -a --exclude .git --exclude build --exclude Config/Local.xcconfig ./ "$WORK/src/"
cd "$WORK/src"

xcodebuild -project Lyricar.xcodeproj -scheme Lyricar -configuration Release -sdk iphoneos \
  -derivedDataPath "$WORK/derived" \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
  APP_BUNDLE_ID="$BUNDLE_ID" SPOTIFY_CLIENT_ID= CALLBACK_SCHEME=lyricar \
  build -quiet

APP="$WORK/derived/Build/Products/Release-iphoneos/Lyricar.app"
cd "$ROOT"

# Entitlements con l'App Group: AltStore & co. li leggono dalla firma e li adattano all'account di chi installa
cat > "$OUT/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.$BUNDLE_ID</string></array>
</dict></plist>
PLIST
codesign -f -s - --entitlements "$OUT/entitlements.plist" "$APP/PlugIns/LyricsWidget.appex"
codesign -f -s - --entitlements "$OUT/entitlements.plist" "$APP"

mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry "$ROOT/build/Lyricar.ipa" Payload)
echo "✓ build/Lyricar.ipa ($(du -h build/Lyricar.ipa | cut -f1))"
