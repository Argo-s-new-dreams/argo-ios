#!/bin/bash
# Screenshot per l'App Store: iPhone 6,9" (1320 × 2868), tema scuro, ora 9:41, dati di prova.
# Compila Argo in Debug per il simulatore e lo avvia in «modalità vetrina» (Argo/Vetrina/Vetrina.swift):
# incontri, persone e aziende inventati, nessun microfono, nessun dato vero.
# Uso: strumenti/screenshot-appstore.sh ["iPhone 17 Pro Max"]
# Risultato: ~/Desktop/Argo-AppStore (cambia con ARGO_SCREENSHOT=/altra/cartella)
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=blog.argosnewdreams.argo
USCITA="${ARGO_SCREENSHOT:-$HOME/Desktop/Argo-AppStore}"
SCHERMATE=(elenco informativa registrazione relazione trascrizione foto)

# Il «Pro Max» più recente installato in Xcode: ha lo schermo da 6,9" che App Store Connect richiede.
NOME="${1:-}"
if [ -z "$NOME" ]; then
  NOME=$(xcrun simctl list devices available | grep -Eo 'iPhone [0-9]+ Pro Max' | sort -t' ' -k2 -n | tail -1 || true)
fi
if [ -z "$NOME" ]; then
  echo "Nessun simulatore «iPhone … Pro Max»: aggiungilo da Xcode › Settings › Components."
  exit 1
fi
UDID=$(xcrun simctl list devices available | grep -F "    $NOME (" | tail -1 | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
echo "Simulatore: $NOME ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

echo "Compilo Argo (Debug, simulatore)…"
xcodegen generate >/dev/null
xcodebuild build -project Argo.xcodeproj -scheme Argo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build/vetrina -quiet
xcrun simctl install "$UDID" build/vetrina/Build/Products/Debug-iphonesimulator/Argo.app

mkdir -p "$USCITA"
numero=0
for schermata in "${SCHERMATE[@]}"; do
  numero=$((numero + 1))
  file="$USCITA/$(printf '%02d' "$numero")-$schermata.png"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -ArgoVetrina "$schermata" -AppleLanguages "(it)" -AppleLocale it_IT >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot --type=png "$file" >/dev/null 2>&1
  # App Store Connect rifiuta le immagini con trasparenza: in quel caso ne faccio anche una copia JPEG.
  if sips -g hasAlpha "$file" | grep -q 'hasAlpha: yes'; then
    sips -s format jpeg -s formatOptions 95 "$file" --out "${file%.png}.jpg" >/dev/null
  fi
  dimensioni=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/ {print $2}' | paste -sd'x' -)
  echo "  $(basename "$file")  $dimensioni"
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear
echo "Fatto: $USCITA"
open "$USCITA"
