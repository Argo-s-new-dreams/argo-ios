"""Scheda dell'App Store in più lingue, dai file metadata/appstore/<lingua>.json.

  scheda_appstore.py stato               versioni, stato e lingue già presenti nella scheda
  scheda_appstore.py prova               controlla i file (limiti di Apple) senza scrivere nulla
  scheda_appstore.py scrivi [versione]   scrive nome, sottotitolo, descrizione, parole chiave, testo
                                         promozionale, novità e indirizzi in tutte le lingue

«scrivi» lavora sulla versione modificabile («Prepare for Submission»); se non c'è e indichi
la versione (per esempio 1.1) la crea. Non invia nulla alla revisione: quello resta in
App Store Connect («Add for Review»). Le «novità» non si scrivono sulla prima versione.

Credenziali: le stesse di testflight.py (~/.argo-chiavi/asc.env e la chiave .p8).
"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from testflight import ambiente, chiama  # noqa: E402
import os  # noqa: E402

CARTELLA = Path(__file__).resolve().parent.parent / "metadata/appstore"
LIMITI = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000, "whatsNew": 4000}
INFO = ("name", "subtitle", "privacyPolicyUrl")
VERSIONE = ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl", "whatsNew")
MODIFICABILI = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def schede():
    dati = {f.stem: json.loads(f.read_text()) for f in sorted(CARTELLA.glob("*.json"))}
    errori = []
    for lingua, d in dati.items():
        for campo, limite in LIMITI.items():
            if len(d.get(campo, "")) > limite:
                errori.append(f"{lingua}: {campo} {len(d[campo])} caratteri (massimo {limite})")
        if len(d.get("keywords", "").encode()) > 100:
            errori.append(f"{lingua}: keywords {len(d['keywords'].encode())} byte (massimo 100)")
    if errori:
        sys.exit("Testi troppo lunghi:\n  " + "\n  ".join(errori))
    return dati


def stato_versione(v):
    a = v["attributes"]
    return a.get("appVersionState") or a.get("appStoreState")


def versioni():
    return chiama("GET", f"/apps/{os.environ['ASC_APP_ID']}/appStoreVersions",
                  params={"filter[platform]": "IOS", "limit": 20})["data"]


def info_modificabile():
    infos = chiama("GET", f"/apps/{os.environ['ASC_APP_ID']}/appInfos")["data"]
    for i in infos:
        if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) != "READY_FOR_DISTRIBUTION":
            return i
    return infos[0]


def stato():
    for v in versioni():
        loc = chiama("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
        lingue = ", ".join(sorted(l["attributes"]["locale"] for l in loc))
        print(f"Versione {v['attributes']['versionString']}: {stato_versione(v)} · lingue: {lingue}")
    i = info_modificabile()
    loc = chiama("GET", f"/appInfos/{i['id']}/appInfoLocalizations")["data"]
    print("Informazioni app: " + ", ".join(f"{l['attributes']['locale']} «{l['attributes'].get('name')}»" for l in loc))


def prova():
    for lingua, d in schede().items():
        print(f"✅ {lingua}: sottotitolo {len(d['subtitle'])}/30 · promozionale {len(d['promotionalText'])}/170 · "
              f"descrizione {len(d['description'])}/4000 · parole chiave {len(d['keywords'].encode())}/100 byte")


def aggiorna(tipo, esistenti, lingua, attributi, relazione):
    attuale = next((l for l in esistenti if l["attributes"]["locale"] == lingua), None)
    if attuale:
        chiama("PATCH", f"/{tipo}/{attuale['id']}",
               json={"data": {"type": tipo, "id": attuale["id"], "attributes": attributi}})
        return "aggiornata"
    chiama("POST", f"/{tipo}", json={"data": {"type": tipo, "attributes": {"locale": lingua, **attributi},
                                              "relationships": relazione}})
    return "aggiunta"


def scrivi(nuova=None):
    dati = schede()
    tutte = versioni()
    v = next((x for x in tutte if stato_versione(x) in MODIFICABILI), None)
    if not v:
        if not nuova:
            sys.exit("Nessuna versione modificabile. Indica quella da creare, per esempio: scrivi 1.1")
        v = chiama("POST", "/appStoreVersions", json={"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": nuova},
            "relationships": {"app": {"data": {"type": "apps", "id": os.environ["ASC_APP_ID"]}}}}})["data"]
        print(f"➕ Creata la versione {nuova} in App Store Connect.")
    prima = not any(x["id"] != v["id"] for x in tutte)
    info = info_modificabile()
    loc_info = chiama("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
    loc_ver = chiama("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
    for lingua, d in dati.items():
        a = {k: d[k] for k in INFO if d.get(k)}
        esito_i = aggiorna("appInfoLocalizations", loc_info, lingua, a,
                           {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}})
        b = {k: d[k] for k in VERSIONE if d.get(k) and not (k == "whatsNew" and prima)}
        esito_v = aggiorna("appStoreVersionLocalizations", loc_ver, lingua, b,
                           {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}})
        print(f"✅ {lingua}: informazioni {esito_i}, scheda della versione {v['attributes']['versionString']} {esito_v}")
    print("Ora in App Store Connect: screenshot per le nuove lingue (se vuoi diversi dall'italiano), poi «Add for Review».")


if __name__ == "__main__":
    comando, *argomenti = sys.argv[1:] or ["?"]
    if comando == "prova":
        prova()
    elif comando in ("stato", "scrivi"):
        ambiente()
        {"stato": stato, "scrivi": scrivi}[comando](*argomenti)
    else:
        sys.exit(__doc__)
