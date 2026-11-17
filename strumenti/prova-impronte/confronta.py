"""confronta.py pyannote.json fluid.json

Dice se le impronte di Argo desktop (pyannote) e di Argo per iPhone (FluidAudio)
vivono nello stesso spazio, cioè se si possono confrontare direttamente.
"""
import json
import sys

import numpy as np


def carica(percorso):
    return {k: np.asarray(v, dtype=np.float32) for k, v in json.load(open(percorso)).items()}


def cos(a, b):
    if a.shape != b.shape:
        return float("nan")
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


def tabella(titolo, sinistra, destra):
    nomi = sorted(set(sinistra) & set(destra))
    print(f"\n{titolo}")
    print(" " * 14 + "".join(f"{n[:12]:>13}" for n in nomi))
    for a in nomi:
        print(f"{a[:13]:<14}" + "".join(f"{cos(sinistra[a], destra[b]):>13.2f}" for b in nomi))


py, fl = carica(sys.argv[1]), carica(sys.argv[2])
dim_py = {v.shape[0] for v in py.values()}
dim_fl = {v.shape[0] for v in fl.values()}
print(f"Dimensioni · pyannote: {sorted(dim_py)} · FluidAudio: {sorted(dim_fl)}")

tabella("pyannote vs pyannote (riferimento: come ragiona oggi Argo desktop)", py, py)
tabella("FluidAudio vs FluidAudio (come ragiona Argo per iPhone)", fl, fl)
tabella("INCROCIO pyannote (righe) vs FluidAudio (colonne)", py, fl)

comuni = sorted(set(py) & set(fl))
if dim_py != dim_fl:
    print("\nVERDETTO: INCOMPATIBILI (dimensioni diverse). Serve un'impronta per motore.")
    sys.exit(0)

diagonale = [cos(py[n], fl[n]) for n in comuni]
media = float(np.mean(diagonale))
print(f"\nStesso audio, motori diversi · somiglianza media: {media:.2f}")
if media >= 0.8:
    print("VERDETTO: COMPATIBILI. L'iPhone può usare direttamente le impronte dell'anagrafe di Argo desktop.")
elif media >= 0.5:
    print("VERDETTO: PARZIALMENTE COMPATIBILI. Stesso spazio ma con deriva: meglio un'impronta per motore,"
          " oppure una soglia dedicata da tarare con più campioni.")
else:
    print("VERDETTO: INCOMPATIBILI. Le impronte vanno calcolate con ciascun motore (un'impronta per motore).")
