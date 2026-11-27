#!/bin/bash
# Archivia Argo, lo carica su App Store Connect e imposta le note «Cosa provare».
# I tester del gruppo interno (distribuzione automatica attiva) ricevono la build da soli.
# Uso: strumenti/pubblica-testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHIAVI="${ARGO_CHIAVI:-$HOME/.argo-chiavi}"; [ -d "$CHIAVI" ] || CHIAVI="$HOME/Documents/ArgoChiavi"
source "$CHIAVI/asc.env"
BUILD=$(cat VERSIONE)
rm -rf build/Argo.xcarchive build/export
mkdir -p build
if [ -n "${ARGO_CI_PROFILO:-}" ]; then
  # GitHub Actions (.github/workflows/testflight.yml): firma manuale con il certificato e il profilo App Store
  # presi dai segreti del repo, caricamento con la chiave API. project-ci.yml è una copia di project.yml con la
  # firma manuale (non va nel repo), così il commit «inviata a TestFlight» non la porta con sé.
  sed -e 's/^    CODE_SIGN_STYLE: Automatic$/    CODE_SIGN_STYLE: Manual/' \
      -e "s/^        PRODUCT_NAME: Argo$/        PRODUCT_NAME: Argo\\
        CODE_SIGN_IDENTITY: \"Apple Distribution\"\\
        PROVISIONING_PROFILE_SPECIFIER: \"$ARGO_CI_PROFILO\"/" project.yml > project-ci.yml
  grep -q "PROVISIONING_PROFILE_SPECIFIER" project-ci.yml || { echo "project-ci.yml senza profilo: controlla project.yml"; exit 1; }
  xcodegen generate --spec project-ci.yml
  CHIAVE_P8="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
  AUTH=(-authenticationKeyPath "$CHIAVE_P8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  OPZIONI=build/ExportOptions-CI.plist
  cat > "$OPZIONI" <<FINE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>WPR2P5Q2S8</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict><key>blog.argosnewdreams.argo</key><string>$ARGO_CI_PROFILO</string></dict>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
	<key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
FINE
  xcodebuild archive -project Argo.xcodeproj -scheme Argo -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/Argo.xcarchive -quiet
else
  # Sul Mac: firma e caricamento con l'account Apple collegato in Xcode (Settings › Accounts): firma nel cloud
  # e profili aggiornati da soli. La chiave API (ruolo App Manager) serve solo a testflight.py.
  AUTH=(-allowProvisioningUpdates)
  OPZIONI=strumenti/ExportOptions-TestFlight.plist
  xcodegen generate
  xcodebuild archive -project Argo.xcodeproj -scheme Argo -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/Argo.xcarchive "${AUTH[@]}" -quiet
fi
xcodebuild -exportArchive -archivePath build/Argo.xcarchive \
  -exportOptionsPlist "$OPZIONI" -exportPath build/export "${AUTH[@]}"
echo "Build $BUILD caricata. Attendo l'elaborazione di Apple per le note…"
uv run --quiet --with pyjwt --with cryptography --with requests strumenti/testflight.py note "$BUILD"
