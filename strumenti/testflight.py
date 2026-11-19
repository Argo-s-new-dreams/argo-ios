"""TestFlight via App Store Connect API.

  testflight.py note <build>                 attende l'elaborazione e scrive «Cosa provare» dal CHANGELOG
  testflight.py stato <build>                stato della build e gruppi a cui è assegnata
  testflight.py esterni <build> "<gruppo>"   assegna la build al gruppo esterno e la invia alla revisione beta

Credenziali in ~/.argo-chiavi/asc.env (o $ARGO_CHIAVI; vecchia sede ~/Documents/ArgoChiavi) (ASC_KEY_ID, ASC_ISSUER_ID, ASC_APP_ID).
"""
import os, re, sys, time
from pathlib import Path
import jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
CHIAVI = Path(os.environ.get("ARGO_CHIAVI", Path.home() / ".argo-chiavi"))
if not CHIAVI.is_dir():
    CHIAVI = Path.home() / "Documents/ArgoChiavi"


def ambiente():
    for riga in (CHIAVI / "asc.env").read_text().splitlines():
        m = re.match(r"\s*(?:export\s+)?(\w+)=[\"']?([^\"'#]*)", riga)
        if m:
            os.environ.setdefault(m[1], m[2].strip())


def intestazioni():
    kid, iss = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    chiave = (Path.home() / f".appstoreconnect/private_keys/AuthKey_{kid}.p8").read_text()
    ora = int(time.time())
    token = jwt.encode({"iss": iss, "iat": ora, "exp": ora + 1100, "aud": "appstoreconnect-v1"},
                       chiave, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})
    return {"Authorization": f"Bearer {token}"}


def chiama(metodo, percorso, **kw):
    r = requests.request(metodo, API + percorso, headers=intestazioni(), timeout=60, **kw)
    if r.status_code >= 400:
        sys.exit(f"App Store Connect {r.status_code}: {r.text[:600]}")
    return r.json() if r.text else {}


def trova_build(build, attesa=1800):
    fine = time.time() + attesa
    while True:
        dati = chiama("GET", "/builds", params={"filter[app]": os.environ["ASC_APP_ID"],
                                                "filter[version]": build, "limit": 1})["data"]
        if dati and dati[0]["attributes"]["processingState"] == "VALID":
            return dati[0]
        if dati and dati[0]["attributes"]["processingState"] in ("FAILED", "INVALID"):
            sys.exit(f"Apple ha scartato la build {build}: {dati[0]['attributes']['processingState']}")
        if time.time() > fine:
            sys.exit(f"Build {build} non ancora elaborata dopo {attesa // 60} minuti: riprova più tardi con «note».")
        time.sleep(30)


def note_dal_changelog(limite=4000):
    testo = Path("CHANGELOG.md").read_text()
    m = re.search(r"^## \[.*?$(.*?)(?=^## \[|\Z)", testo, re.S | re.M)
    corpo = m[1] if m else ""
    corpo = re.sub(r"\*\*|`|^### ", "", corpo, flags=re.M)
    return re.sub(r"\n{3,}", "\n\n", corpo).strip()[:limite]


def note(build):
    b = trova_build(build)
    testo = note_dal_changelog()
    loc = chiama("GET", f"/builds/{b['id']}/betaBuildLocalizations")["data"]
    it = next((l for l in loc if l["attributes"]["locale"].startswith("it")), None)
    if it:
        chiama("PATCH", f"/betaBuildLocalizations/{it['id']}", json={"data": {
            "type": "betaBuildLocalizations", "id": it["id"], "attributes": {"whatsNew": testo}}})
    else:
        chiama("POST", "/betaBuildLocalizations", json={"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "it", "whatsNew": testo},
            "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
    print(f"✅ Build {build} elaborata, note «Cosa provare» scritte ({len(testo)} caratteri).")


def stato(build):
    b = trova_build(build, attesa=0)
    gruppi = chiama("GET", f"/builds/{b['id']}/betaGroups")["data"]
    nomi = ", ".join(f"{g['attributes']['name']}{' (interno)' if g['attributes']['isInternalGroup'] else ''}" for g in gruppi)
    print(f"Build {build}: {b['attributes']['processingState']} · gruppi: {nomi or 'nessuno'}")


def esterni(build, nome_gruppo):
    b = trova_build(build)
    gruppi = chiama("GET", "/betaGroups", params={"filter[app]": os.environ["ASC_APP_ID"],
                                                  "filter[name]": nome_gruppo})["data"]
    if not gruppi:
        sys.exit(f"Gruppo «{nome_gruppo}» non trovato in TestFlight.")
    chiama("POST", f"/betaGroups/{gruppi[0]['id']}/relationships/builds",
           json={"data": [{"type": "builds", "id": b["id"]}]})
    r = requests.post(API + "/betaAppReviewSubmissions", headers=intestazioni(), timeout=60, json={"data": {
        "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
    if r.status_code >= 400 and "already" not in r.text.lower():
        sys.exit(f"Build assegnata a «{nome_gruppo}», ma l'invio alla revisione beta è fallito: {r.text[:600]}")
    print(f"✅ Build {build} assegnata a «{nome_gruppo}» e inviata alla revisione beta di Apple.")


if __name__ == "__main__":
    ambiente()
    comando, *argomenti = sys.argv[1:] or ["?"]
    {"note": note, "stato": stato, "esterni": esterni}.get(comando, lambda *a: sys.exit(__doc__))(*argomenti)
