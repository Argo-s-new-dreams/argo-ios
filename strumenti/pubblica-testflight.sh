#!/bin/bash
# Archivia Argo, lo carica su App Store Connect e imposta le note «Cosa provare».
# I tester del gruppo interno (distribuzione automatica attiva) ricevono la build da soli.
# Uso: strumenti/pubblica-testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source "$HOME/Documents/ArgoChiavi/asc.env"
CHIAVE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$CHIAVE" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
BUILD=$(cat VERSIONE)
xcodegen generate
rm -rf build/Argo.xcarchive build/export
xcodebuild archive -project Argo.xcodeproj -scheme Argo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Argo.xcarchive "${AUTH[@]}" -quiet
xcodebuild -exportArchive -archivePath build/Argo.xcarchive \
  -exportOptionsPlist strumenti/ExportOptions-TestFlight.plist -exportPath build/export "${AUTH[@]}"
echo "Build $BUILD caricata. Attendo l'elaborazione di Apple per le note…"
uv run --quiet --with pyjwt --with cryptography --with requests strumenti/testflight.py note "$BUILD"
