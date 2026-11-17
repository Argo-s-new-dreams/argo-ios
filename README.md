# Argo per iPhone

Il fratello tascabile di [Argo · Cassetta degli attrezzi AI](https://github.com/Argo-s-new-dreams/argo-ai): **registra una riunione, la trascrive e crea il verbale, tutto sul tuo iPhone**. Niente cloud, niente server, niente account.

🔒 100% locale · iOS 26 · SwiftUI

## Cosa fa (v0.1)

| Funzione | Come | Dove gira |
|---|---|---|
| **Registra** | Microfono, AAC mono 16 kHz, continua anche a schermo bloccato | iPhone |
| **Trascrivi** | `SpeechAnalyzer` + `SpeechTranscriber` (framework Speech, iOS 26) con marche temporali | iPhone |
| **Verbale** | Foundation Models (Apple Intelligence) con guided generation: titolo, riassunto, punti chiave, azioni | iPhone con Apple Intelligence |
| **Verbale dal Mac** | Ollama sul tuo Mac in rete locale, output JSON strutturato | Mac (Wi-Fi di casa/ufficio) |
| **Condividi** | Verbale in Markdown verso Mail, Note, Teams, File… | — |
| **Importa** | Qualsiasi file audio (Memo Vocali, File) | iPhone |

**Privacy by design**, come Argo sul Mac:
- informativa da confermare prima di ogni registrazione;
- opzione (attiva di default) per **eliminare l'audio appena trascritto**: resta solo il testo;
- nessuna chiamata di rete, tranne il download dei modelli linguistici gestito da iOS.

## Requisiti

- Xcode 26 o successivo, macOS con Apple Silicon
- iPhone con iOS 26
- Qualsiasi iPhone con iOS 26 (iPhone 11 e successivi, SE di 2ª generazione e successivi): registrazione e trascrizione funzionano ovunque
- Per il verbale, una delle due:
  - iPhone con Apple Intelligence (15 Pro e successivi), tutto sul telefono;
  - il tuo Mac con [Ollama](https://ollama.com) sulla stessa rete Wi-Fi.
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

## Verbale dal Mac (iPhone senza Apple Intelligence)

1. Sul Mac, fai accettare a Ollama le connessioni dalla rete locale. Puoi usare l'opzione di rete nelle impostazioni dell'app Ollama, se la tua versione la prevede, oppure:
   ```bash
   launchctl setenv OLLAMA_HOST "0.0.0.0"
   ```
   poi chiudi e riapri Ollama. Se il firewall di macOS chiede conferma, consenti.
2. Sull'iPhone: *Impostazioni › Verbale*, scegli **Automatico** o **Il mio Mac**, scrivi `nome-del-mac.local` (lo trovi in *Impostazioni di Sistema › Generali › Condivisione › Nome host locale*), premi **Prova connessione** e scegli il modello.
3. Alla prima richiesta iOS chiede il permesso per la rete locale: consenti.

> ⚠️ Con `OLLAMA_HOST=0.0.0.0` Ollama risponde a chiunque sia sulla stessa rete, senza autenticazione. Va bene a casa; su reti condivise (ufficio, hotel) valuta di disattivarlo quando non serve.

## Struttura

```
Argo/
├── ArgoApp.swift
├── Modello/Sessione.swift          SwiftData: sessione, azioni, export Markdown
├── Servizi/
│   ├── Registratore.swift          AVAudioRecorder, livelli, interruzioni
│   ├── Trascrittore.swift          SpeechAnalyzer / SpeechTranscriber
│   ├── Verbalista.swift            scelta del motore, Apple Intelligence, riduzione a blocchi
│   ├── MotoreOllama.swift          verbale dal Mac via API Ollama
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
- [x] Verbale dal Mac con Ollama in rete locale
- [ ] Trascrizione dal Mac con Argo desktop (WhisperX + diarizzazione)
- [ ] Modello linguistico piccolo direttamente sull'iPhone (MLX) per i telefoni senza Apple Intelligence, anche lontano dal Mac
- [ ] Riconoscimento dei parlanti
- [ ] TestFlight per i colleghi del CC AI

## Licenza

Da definire, allineata ad [argo-ai](https://github.com/Argo-s-new-dreams/argo-ai).
