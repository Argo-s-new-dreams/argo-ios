#!/bin/bash
# Nuovo numero di build (AAAAMMGG.HHMM, ora di Roma) in project.yml e VERSIONE, poi rigenera il progetto.
# TestFlight e App Store Connect rifiutano un caricamento con un numero di build già usato.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=$(TZ=Europe/Rome date +%Y%m%d.%H%M)
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9.]+\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
echo "$BUILD" > VERSIONE
xcodegen generate
echo "Build $BUILD pronta: in Xcode Product › Archive, poi Distribute App › App Store Connect."
