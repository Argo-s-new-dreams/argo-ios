# Argo per iPhone

Il fratello tascabile di [Argo · Cassetta degli attrezzi AI](https://github.com/Argo-s-new-dreams/argo-ai): **registra una riunione, la trascrive e crea il verbale, tutto sul tuo iPhone**. Niente cloud, niente server, niente account.

🔒 100% locale · iOS 26 · SwiftUI

## Cosa fa (v0.1)

| Funzione | Come | Dove gira |
|---|---|---|
| **Registra** | Microfono, AAC mono 16 kHz, continua anche a schermo bloccato | iPhone |
| **Trascrivi** | `SpeechAnalyzer` + `SpeechTranscriber` (framework Speech, iOS 26) con marche temporali | iPhone |
| **Verbale** | Foundation Models (Apple Intelligence) con guided generation: titolo, riassunto, punti chiave, azioni | iPhone |
| **Condividi** | Verbale in Markdown verso Mail, Note, Teams, File… | — |
| **Importa** | Qualsiasi file audio (Memo Vocali, File) | iPhone |

**Privacy by design**, come Argo sul Mac:
- informativa da confermare prima di ogni registrazione;
- opzione (attiva di default) per **eliminare l'audio appena trascritto**: resta solo il testo;
- nessuna chiamata di rete, tranne il download dei modelli linguistici gestito da iOS.

## Requisiti

- Xcode 26 o successivo, macOS con Apple Silicon
- iPhone con iOS 26
- Per il verbale: iPhone compatibile con Apple Intelligence (iPhone 15 Pro o successivi) e Apple Intelligence attiva. Sugli altri iPhone la trascrizione funziona, il verbale no.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) per generare il progetto Xcode

## Primo avvio

```bash
brew install xcodegen
git clone https://github.com/Argo-s-new-dreams/argo-ios.git
cd argo-ios
xcodegen generate
open Argo.xcodeproj
```

In Xcode: target **Argo** › *Signing & Capabilities* › scegli il tuo Team, collega l'iPhone e premi ▶︎.
Per non sceglierlo ogni volta, scrivi il tuo Team ID in `project.yml` (`DEVELOPMENT_TEAM`).

> `Argo.xcodeproj` non è nel repository: si rigenera con `xcodegen generate` ogni volta che aggiungi file.

## Struttura

```
Argo/
├── ArgoApp.swift
├── Modello/Sessione.swift          SwiftData: sessione, azioni, export Markdown
├── Servizi/
│   ├── Registratore.swift          AVAudioRecorder, livelli, interruzioni
│   ├── Trascrittore.swift          SpeechAnalyzer / SpeechTranscriber
│   ├── Verbalista.swift            Foundation Models, riduzione a blocchi
│   └── Elaborazione.swift          audio → trascrizione → verbale
├── Viste/                          SwiftUI (Liquid Glass, tema scuro)
└── Risorse/Assets.xcassets         icona e colore d'accento
```

## Note tecniche

- **Contesto del modello on-device:** circa 4.000 token. Le trascrizioni lunghe vengono riassunte a blocchi da circa 5.000 caratteri, poi unite nel verbale finale (fino a tre passaggi).
- **Call Teams:** iOS non permette di registrare l'audio di altre app. Argo registra il microfono, quindi va bene per riunioni in presenza o in vivavoce, non per una call in cuffia.

## Da fare

- [ ] Icona dal logo originale (Icona_AND) e colori del Brand Book di Argo's New Dreams
- [ ] Trascrizione live durante la registrazione (`SpeechAnalyzer` con input da `AVAudioEngine`)
- [ ] Azioni verso Promemoria (EventKit) e Planner
- [ ] Modalità «usa il mio Mac»: elaborazione con Argo desktop in rete locale (WhisperX + Ollama + diarizzazione)
- [ ] Riconoscimento dei parlanti
- [ ] TestFlight per i colleghi del CC AI

## Licenza

Da definire, allineata ad [argo-ai](https://github.com/Argo-s-new-dreams/argo-ai).
