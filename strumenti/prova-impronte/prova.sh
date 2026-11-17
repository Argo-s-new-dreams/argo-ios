#!/bin/bash
# Test di compatibilità impronte vocali: Argo desktop (pyannote) vs Argo per iPhone (FluidAudio).
# Uso: ./prova.sh io_1.m4a io_2.m4a altro.m4a
# Ogni file: UNA sola persona che parla, 20-30 secondi. Ideale: due tuoi audio diversi + uno di un'altra persona.
set -euo pipefail
cd "$(dirname "$0")"
APP="${TRASCRITTORE_HOME:-$HOME/whisperx-env}"
PY="$APP/bin/python"
export PATH="$APP/bin:$PATH"

[ $# -ge 2 ] || { echo "Servono almeno 2 file audio (meglio 3: due tuoi e uno di un'altra persona)."; exit 1; }
[ -x "$PY" ] || { echo "Non trovo il Python di Argo in $APP"; exit 1; }
command -v swift >/dev/null || { echo "Serve Swift (Xcode)."; exit 1; }

LAVORO="$(mktemp -d)"
trap 'rm -rf "$LAVORO"' EXIT
WAV=()
for f in "$@"; do
  nome="$(basename "${f%.*}")"
  ffmpeg -loglevel error -y -i "$f" -ac 1 -ar 16000 "$LAVORO/$nome.wav"
  WAV+=("$LAVORO/$nome.wav")
done

echo "1/3 · Compilo il calcolatore FluidAudio (la prima volta scarica il pacchetto)…"
if ! swift build -c release --product impronta-fluid > "$LAVORO/build.log" 2>&1; then
  echo "Compilazione non riuscita. Errori:"
  grep -E "error:|warning: .*FluidAudio" "$LAVORO/build.log" | grep -v "^Failed frontend" | head -20
  cp "$LAVORO/build.log" ./build.log
  echo "Log completo in $(pwd)/build.log"
  exit 1
fi

echo "2/3 · Impronte FluidAudio (motore iPhone)…"
.build/release/impronta-fluid "$LAVORO/fluid.json" "${WAV[@]}" 2>&1 | grep -v "^\[Profiling\]" || true

echo "3/3 · Impronte pyannote (motore Argo desktop)…"
PYTHONWARNINGS=ignore "$PY" impronta_pyannote.py "$LAVORO/pyannote.json" "${WAV[@]}" 2>&1 | grep "valori" || true
[ -s "$LAVORO/fluid.json" ] && [ -s "$LAVORO/pyannote.json" ] || { echo "Impronte non calcolate: rilancia per vedere gli errori."; exit 1; }

"$PY" confronta.py "$LAVORO/pyannote.json" "$LAVORO/fluid.json" | tee risultato.txt
echo
echo "Risultato salvato in $(pwd)/risultato.txt (nessun audio conservato)."
