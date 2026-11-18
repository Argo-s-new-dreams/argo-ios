# Argo per iPhone

Il fratello tascabile di [Argo · Cassetta degli attrezzi AI](https://github.com/Argo-s-new-dreams/argo-ai): **un taccuino per riunioni e fiere**. Registri la conversazione, fotografi biglietti da visita e documenti mentre parli, e Argo trascrive, divide le voci, legge le foto e scrive una relazione coerente. L'audio non resta sul telefono. Niente cloud, niente account.

🔒 100% locale · iOS 26 · SwiftUI

## Cosa fa

| Funzione | Come | Dove gira |
|---|---|---|
| **Registra** | Microfono, PCM mono 16 kHz (file che resta leggibile anche se la registrazione si interrompe), continua anche a schermo bloccato | iPhone |
| **Foto** | Scatti durante la registrazione, agganciati al secondo della conversazione | iPhone |
| **Testo delle foto** | OCR con Apple Vision + riconoscimento di telefoni, email, siti | iPhone |
| **Voci** | Diarizzazione con [FluidAudio](https://github.com/FluidInference/FluidAudio) (pyannote in CoreML), parlanti rinominabili | iPhone |
| **La mia voce** | Profilo voce registrato una volta: Argo ti riconosce e ti separa dagli interlocutori | iPhone |
| **Anagrafe voci** | Le persone dell'anagrafe di Argo desktop, importate con AirDrop (`.argovoci`), riconosciute per nome | iPhone |
| **Trascrivi** | `SpeechAnalyzer` + `SpeechTranscriber` (framework Speech, iOS 26) con marche temporali | iPhone |
| **Verbale** | Foundation Models (Apple Intelligence) con guided generation: titolo, riassunto, punti chiave, azioni | iPhone con Apple Intelligence |
| **Verbale dal Mac** | Ollama sul tuo Mac in rete locale, output JSON strutturato | Mac (Wi-Fi di casa/ufficio) |
| **Pacchetto Argo** | .zip con `sessione.json`, relazione e foto, via AirDrop/File verso Argo desktop ([formato](docs/FORMATO-PACCHETTO.md)) | — |
| **Ponte con Argo desktop** | Canale cifrato in rete locale (QR + pinning): incontri al computer, anagrafe voci all'iPhone, in automatico ([protocollo](https://github.com/Argo-s-new-dreams/argo-ai/blob/main/docs/PONTE.md)) | rete locale |
| **Condividi** | Relazione in Markdown verso Mail, Note, Teams… | — |
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

Il Team è già in `project.yml` (`DEVELOPMENT_TEAM: WPR2P5Q2S8`, account Apple Developer di Argo's New Dreams): collega l'iPhone e premi ▶︎. Chi compila con un altro account cambia quel valore con il proprio Team ID.

> `Argo.xcodeproj` non è nel repository: si rigenera con `xcodegen generate` ogni volta che aggiungi file.

## Distribuire con TestFlight

Per installare Argo su altri iPhone (famiglia, colleghi) senza cavo.

**Una volta sola**, in [App Store Connect](https://appstoreconnect.apple.com): *App › + › Nuova app*, piattaforma iOS, bundle ID `blog.argosnewdreams.argo`, uno SKU a scelta (es. `argo-ios`). Il nome sullo Store deve essere unico: per esempio «Argo · Taccuino». Se il bundle ID risulta già usato (registrato a suo tempo dal Personal Team), cambialo in `project.yml`.

**A ogni rilascio:**

1. `strumenti/nuova-build.sh`: nuovo numero di build (AAAAMMGG.HHMM) e progetto rigenerato.
2. Xcode: destinazione *Any iOS Device (arm64)* › *Product › Archive*.
3. Organizer: *Distribute App › App Store Connect › Upload*.
4. App Store Connect › TestFlight: quando la build è elaborata, assegnala a un gruppo.
   - **Interno**: persone aggiunte in *Utenti e accessi*; nessuna revisione.
   - **Esterno**: basta l'email (o un link pubblico); la prima build passa una breve revisione beta di Apple.
5. Chi prova installa **TestFlight** dall'App Store e accetta l'invito; le build successive arrivano da sole.

La crittografia è dichiarata in `Info.plist` (`ITSAppUsesNonExemptEncryption: false`: solo HTTPS/TLS del sistema), quindi App Store Connect non chiede la conformità all'esportazione a ogni build. Le build TestFlight scadono dopo un periodo fisso: caricane una nuova prima della scadenza.

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

## Il caso d'uso: la fiera

1. Allo stand avvii la registrazione e informi l'interlocutore.
2. Ti dà un biglietto da visita o una brochure: tocchi 📷 e scatti, senza fermare la registrazione.
3. A fine incontro premi stop: l'iPhone trascrive, divide le voci, legge le foto ed **elimina l'audio**.
4. In albergo, sulla stessa Wi-Fi del portatile con Argo aperto, l'incontro arriva da solo nella pagina **Incontri** di Argo desktop tramite il **Ponte**; da lì relazione e, a seguire, Dynamics 365 Sales.

## Note tecniche

- **Contesto del modello on-device:** circa 4.000 token. Le trascrizioni lunghe vengono riassunte a blocchi da circa 5.000 caratteri, poi unite nel verbale finale (fino a tre passaggi).
- **Primo utilizzo:** il modello della lingua (Apple) e quelli di diarizzazione (FluidAudio, da Hugging Face) si scaricano la prima volta; poi tutto funziona offline. Conviene fare una prova prima di partire per la fiera.
- **Licenze:** prima della distribuzione verificare le licenze di FluidAudio e dei modelli di diarizzazione che scarica (vedi Fase 4 della roadmap Argo Pro).
- **Call Teams:** iOS non permette di registrare l'audio di altre app. Argo registra il microfono, quindi va bene per riunioni in presenza o in vivavoce, non per una call in cuffia.

## Da fare

- [ ] Icona dal logo originale (Icona_AND) e colori del Brand Book di Argo's New Dreams
- [ ] Trascrizione live durante la registrazione (`SpeechAnalyzer` con input da `AVAudioEngine`)
- [ ] Azioni verso Promemoria (EventKit) e Planner
- [x] Verbale dal Mac con Ollama in rete locale
- [ ] Trascrizione dal Mac con Argo desktop (WhisperX + diarizzazione)
- [ ] Modello linguistico piccolo direttamente sull'iPhone (MLX) per i telefoni senza Apple Intelligence, anche lontano dal Mac
- [x] Riconoscimento dei parlanti
- [x] Foto durante la registrazione, OCR, pacchetto per il Mac
- [ ] Import del pacchetto in Argo desktop (Mac, poi Windows) e relazione con modello vision
- [ ] Connettore Dynamics 365 Sales
- [ ] App Android che produce lo stesso pacchetto
- [ ] TestFlight per i colleghi del CC AI

## Licenza

Da definire, allineata ad [argo-ai](https://github.com/Argo-s-new-dreams/argo-ai).
