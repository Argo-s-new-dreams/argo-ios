#!/bin/bash
# Archivia Argo, lo carica su App Store Connect e imposta le note «Cosa provare».
# I tester del gruppo interno (distribuzione automatica attiva) ricevono la build da soli.
# Uso: strumenti/pubblica-testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHIAVI="${ARGO_CHIAVI:-$HOME/.argo-chiavi}"; [ -d "$CHIAVI" ] || CHIAVI="$HOME/Documents/ArgoChiavi"
source "$CHIAVI/asc.env"
# Firma e caricamento con l'account Apple collegato in Xcode (Settings › Accounts): firma nel cloud
# e profili aggiornati da soli. La chiave API (ruolo App Manager) serve solo a testflight.py.
AUTH=(-allowProvisioningUpdates)
BUILD=$(cat VERSIONE)
xcodegen generate
rm -rf build/Argo.xcarchive build/export
xcodebuild archive -project Argo.xcodeproj -scheme Argo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Argo.xcarchive "${AUTH[@]}" -quiet
xcodebuild -exportArchive -archivePath build/Argo.xcarchive \
  -exportOptionsPlist strumenti/ExportOptions-TestFlight.plist -exportPath build/export "${AUTH[@]}"
echo "Build $BUILD caricata. Attendo l'elaborazione di Apple per le note…"
uv run --quiet --with pyjwt --with cryptography --with requests strumenti/testflight.py note "$BUILD"
