#!/bin/bash
# Manda ai tester una nuova build solo se su main ci sono modifiche dall'ultimo invio
# (con la loro voce nel CHANGELOG). Lo lancia launchd ogni notte; a mano:
#   strumenti/pubblica-se-serve.sh           pubblica se serve
#   strumenti/pubblica-se-serve.sh --forza   pubblica comunque (stesse note dell'ultima voce)
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$(basename "$PWD")
LOG="$HOME/Library/Logs/Argo/$REPO.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
avvisa() { osascript -e "display notification \"$2\" with title \"Argo · $REPO\" subtitle \"$1\"" >/dev/null 2>&1 || true; }
echo "=== $(date '+%Y-%m-%d %H:%M') · $REPO"

if [ -f strumenti/pubblica-testflight.sh ]; then
  PUBBLICA=strumenti/pubblica-testflight.sh; DOVE="TestFlight"; ESCLUSI=(':!VERSIONE' ':!project.yml')
else
  PUBBLICA=strumenti/pubblica-play.sh; DOVE="test interno di Google Play"; ESCLUSI=(':!VERSIONE')
fi

BLOCCO="/tmp/argo-$REPO.lock"
mkdir "$BLOCCO" 2>/dev/null || { echo "Una pubblicazione è già in corso."; exit 0; }
trap 'rmdir "$BLOCCO"' EXIT

if ! git pull --autostash --quiet; then
  echo "git pull non riuscito (rete, conflitto o permessi sulla cartella)."
  avvisa "Pubblicazione non partita" "git pull non riuscito: vedi ~/Library/Logs/Argo/$REPO.log"
  exit 1
fi

ULTIMO=$(git log -1 --format=%H --grep="inviata a")
if [ "${1:-}" != "--forza" ] && [ -n "$ULTIMO" ]; then
  CAMBIATI=$(git diff --name-only "$ULTIMO" HEAD -- . "${ESCLUSI[@]}")
  if [ -z "$CAMBIATI" ]; then
    echo "Niente di nuovo dall'ultimo invio ($(git log -1 --format=%s "$ULTIMO"))."
    exit 0
  fi
  if ! grep -qx "CHANGELOG.md" <<<"$CAMBIATI"; then
    echo "Ci sono modifiche ma nessuna voce nuova nel CHANGELOG: non pubblico."
    avvisa "In attesa" "Modifiche senza voce nel CHANGELOG"
    exit 0
  fi
  echo "Novità dall'ultimo invio:"; echo "$CAMBIATI" | sed 's/^/  /'
fi

if strumenti/nuova-build.sh && "$PUBBLICA" \
   && git commit -qam "Build $(cat VERSIONE) inviata a $DOVE" && git push -q; then
  echo "✅ Build $(cat VERSIONE) inviata a $DOVE."
  avvisa "Inviata ai tester" "Build $(cat VERSIONE) su $DOVE"
else
  echo "❌ Pubblicazione fallita."
  avvisa "Pubblicazione fallita" "Dettagli in ~/Library/Logs/Argo/$REPO.log"
  exit 1
fi
