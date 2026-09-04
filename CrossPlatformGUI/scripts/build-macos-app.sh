#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT_DIR/EntraMailSendRbac.Gui/EntraMailSendRbac.Gui.csproj"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Entra MailSend RBAC"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

if ! command -v dotnet >/dev/null 2>&1; then
  echo "Fehler: .NET SDK wurde nicht gefunden. Bitte .NET 8 SDK oder neuer installieren."
  exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo "Fehler: PowerShell 7 wurde nicht gefunden. Bitte PowerShell 7.4 oder neuer installieren."
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) RID="osx-arm64" ;;
  x86_64) RID="osx-x64" ;;
  *) echo "Nicht unterstützte macOS-Architektur: $ARCH"; exit 1 ;;
esac

PUBLISH_DIR="$DIST_DIR/publish-$RID"
rm -rf "$PUBLISH_DIR" "$APP_BUNDLE"
mkdir -p "$PUBLISH_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "Veröffentliche für $RID …"
dotnet publish "$PROJECT" \
  -c Release \
  -r "$RID" \
  --self-contained true \
  -p:PublishSingleFile=false \
  -o "$PUBLISH_DIR"

cp -R "$PUBLISH_DIR"/. "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/EntraMailSendRbac.Gui"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Entra MailSend RBAC</string>
  <key>CFBundleExecutable</key>
  <string>EntraMailSendRbac.Gui</string>
  <key>CFBundleIdentifier</key>
  <string>de.alhnedi.entramailsendrbac</string>
  <key>CFBundleName</key>
  <string>Entra MailSend RBAC</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo
echo "Fertig:"
echo "$APP_BUNDLE"
echo
echo "Die App ist lokal gebaut und nicht mit einem Apple Developer-Zertifikat signiert/notarisiert."
echo "Zum Testen kann sie direkt aus dem Finder geöffnet werden."
