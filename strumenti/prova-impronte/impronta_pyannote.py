"""impronta_pyannote.py uscita.json file1.wav [file2.wav …]

Calcola le impronte esattamente come l'anagrafe voci di Argo desktop (voci_core.iscrivi):
WhisperX DiarizationPipeline (pyannote community-1), num_speakers=1, return_embeddings=True.
Va lanciato con il Python di Argo: ~/whisperx-env/bin/python
"""
import json
import os
import sys
from pathlib import Path

APP = Path(os.environ.get("TRASCRITTORE_HOME", Path.home() / "whisperx-env"))
sys.path.insert(0, str(APP / "app"))
os.environ.setdefault("PYANNOTE_METRICS_ENABLED", "0")

from voci_core import leggi_token  # noqa: E402
from whisperx.diarize import DiarizationPipeline  # noqa: E402

pipe = DiarizationPipeline(token=leggi_token(), device="cpu")
risultati = {}
uscita = Path(sys.argv[1])
for percorso in sys.argv[2:]:
    _, emb = pipe(percorso, num_speakers=1, return_embeddings=True)
    if not emb:
        sys.exit(f"Nessuna voce trovata in {percorso}")
    vettore = [float(x) for x in next(iter(emb.values()))]
    risultati[Path(percorso).stem] = vettore
    print(f"pyannote · {percorso}: {len(vettore)} valori", file=sys.stderr, flush=True)
# Su file: WhisperX e pyannote possono scrivere sullo standard output.
uscita.write_text(json.dumps(risultati, sort_keys=True))
