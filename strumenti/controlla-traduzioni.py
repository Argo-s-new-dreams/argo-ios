#!/usr/bin/env python3
"""Controlla le traduzioni esportate da Xcode (xcodebuild -exportLocalizations).

Uso: strumenti/controlla-traduzioni.py <cartella con en.xcloc, es.xcloc, de.xcloc>
Elenca i testi dell'app senza traduzione in inglese, spagnolo o tedesco ed esce con errore se ce ne sono.
"""
import pathlib
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
cartella = pathlib.Path(sys.argv[1])
mancanti = 0
for lingua in ("en", "es", "de"):
    for xliff in cartella.glob(f"{lingua}.xcloc/Localized Contents/*.xliff"):
        for file in ET.parse(xliff).getroot().findall("x:file", NS):
            origine = file.get("original", "")
            for unita in file.iter(f"{{{NS['x']}}}trans-unit"):
                if unita.get("translate") == "no":
                    continue
                testo = unita.findtext("x:source", default="", namespaces=NS)
                bersaglio = unita.find("x:target", NS)
                if not testo.strip() or testo.strip() in {"%lld", "%@"}:
                    continue
                if bersaglio is None or not (bersaglio.text or "").strip():
                    mancanti += 1
                    print(f"[{lingua}] {origine}: {testo!r}")
print(f"Testi senza traduzione: {mancanti}")
sys.exit(1 if mancanti else 0)
