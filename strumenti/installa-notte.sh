#!/bin/bash
# Programma con launchd la pubblicazione notturna di questo repo (solo se ci sono novità).
#   strumenti/installa-notte.sh 02:30    installa o cambia l'orario
#   strumenti/installa-notte.sh --togli  toglie la programmazione
# Se il Mac dorme a quell'ora, launchd la esegue al risveglio.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$(basename "$PWD")
ETICHETTA="blog.argosnewdreams.$REPO.notte"
PLIST="$HOME/Library/LaunchAgents/$ETICHETTA.plist"
DOMINIO="gui/$(id -u)"
launchctl bootout "$DOMINIO/$ETICHETTA" 2>/dev/null || true
if [ "${1:-}" = "--togli" ]; then
  rm -f "$PLIST"; echo "Pubblicazione notturna di $REPO tolta."; exit 0
fi
ORA="${1:-02:30}"
H=$((10#${ORA%%:*})); M=$((10#${ORA##*:}))
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/Argo"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$ETICHETTA</string>
	<key>ProgramArguments</key>
	<array><string>/bin/bash</string><string>$PWD/strumenti/pubblica-se-serve.sh</string></array>
	<key>StartCalendarInterval</key>
	<dict><key>Hour</key><integer>$H</integer><key>Minute</key><integer>$M</integer></dict>
	<key>EnvironmentVariables</key>
	<dict><key>PATH</key><string>$PATH</string></dict>
	<key>StandardOutPath</key><string>$HOME/Library/Logs/Argo/$REPO-launchd.log</string>
	<key>StandardErrorPath</key><string>$HOME/Library/Logs/Argo/$REPO-launchd.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMINIO" "$PLIST"
printf 'Ogni notte alle %02d:%02d %s va ai tester, se ci sono novità.\n' "$H" "$M" "$REPO"
echo "Prova subito: launchctl kickstart $DOMINIO/$ETICHETTA   ·   log: ~/Library/Logs/Argo/$REPO.log"
