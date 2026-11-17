# Pacchetto Argo · formato `argo.sessione` v1

Il pacchetto è il ponte tra i dispositivi: lo crea Argo per iPhone (domani anche Android) e lo leggono Argo desktop su Mac e Windows e, più avanti, il connettore per Dynamics 365 Sales.

È un normale **.zip**, apribile ovunque senza software particolare.

```
Argo-2026-11-17-0958-Incontro-stand-Rossi.zip
└── Argo-2026-11-17-0958-Incontro-stand-Rossi/
    ├── sessione.json      dati strutturati (questo documento)
    ├── relazione.md       relazione + trascrizione, leggibile da chiunque
    └── foto/
        ├── 01.jpg         in ordine di scatto
        └── 02.jpg
```

**L'audio non c'è mai**: il pacchetto contiene solo testo e foto.

## sessione.json

| Campo | Tipo | Note |
|---|---|---|
| `formato` | string | sempre `"argo.sessione"` |
| `versioneFormato` | int | `1`. Si incrementa solo per modifiche non compatibili |
| `app` | string | es. `"Argo per iPhone 0.3.0"` |
| `id` | UUID | identificativo stabile della sessione (utile per non importare due volte) |
| `creata` | ISO 8601 | inizio della registrazione |
| `titolo`, `lingua` | string | lingua come codice BCP-47, es. `it-IT` |
| `durata` | number | secondi |
| `partecipanti[]` | `{id, nome}` | `id` = `P1`, `P2`… in ordine di prima apparizione; `nome` scelto dall'utente o «Parlante N» |
| `segmenti[]` | `{inizio, fine, parlante?, testo}` | secondi dall'inizio; `parlante` = id del partecipante, assente se la diarizzazione non è riuscita |
| `foto[]` | `{file, secondo, testo, riferimenti[]}` | `secondo` = momento dello scatto sulla stessa linea temporale dei segmenti; `testo` = OCR; `riferimenti` = telefoni, email, siti, indirizzi riconosciuti |
| `relazione` | oggetto o `null` | presente se la relazione è già stata generata sul telefono |
| `relazione.motore` | string | es. `"Apple Intelligence"`, `"Mac · qwen3:8b"` |
| `relazione.riassunto` | string | |
| `relazione.puntiChiave[]` | string | |
| `relazione.azioni[]` | `{descrizione, responsabile?, scadenza?}` | |
| `relazione.contatti[]` | `{nome, azienda?, ruolo?, email?, telefono?, note?}` | base per lead/contatti in Dynamics 365 |
| `trascrizioneLegacy` | string o `null` | solo per sessioni create prima della 0.3, senza segmenti |

### Esempio

```json
{
  "formato": "argo.sessione",
  "versioneFormato": 1,
  "app": "Argo per iPhone 0.3.0",
  "id": "6F1C2D7E-0B1A-4C55-9A0E-2B4D1E9F7A10",
  "creata": "2026-11-17T08:58:00Z",
  "titolo": "Incontro stand Rossi Automazione",
  "lingua": "it-IT",
  "durata": 412.5,
  "partecipanti": [
    { "id": "P1", "nome": "Io" },
    { "id": "P2", "nome": "Mario Rossi" }
  ],
  "segmenti": [
    { "inizio": 0.8, "fine": 6.2, "parlante": "P1", "testo": "Buongiorno, vedo che fate visione artificiale." },
    { "inizio": 6.9, "fine": 14.0, "parlante": "P2", "testo": "Sì, per il controllo qualità sulle linee di confezionamento." }
  ],
  "foto": [
    {
      "file": "foto/01.jpg",
      "secondo": 15.3,
      "testo": "Mario Rossi\nSales Manager\nRossi Automazione S.r.l.\nmario.rossi@esempio.it",
      "riferimenti": ["mario.rossi@esempio.it"]
    }
  ],
  "relazione": null,
  "trascrizioneLegacy": null
}
```

## Regole per chi legge il pacchetto

- Controllare `formato` e `versioneFormato`; ignorare i campi sconosciuti (così le versioni future restano leggibili).
- Ordinare segmenti e foto per tempo e intercalarli: è la «cronologia» da dare al modello per la relazione.
- Usare `id` per riconoscere un pacchetto già importato.
- Trattare il contenuto come **dati personali**: chi lo importa decide conservazione e cancellazione.
