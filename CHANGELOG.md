# Changelog

Tutte le modifiche rilevanti di Argo per iPhone.
Versioni: `MARKETING_VERSION` (semver) + build `AAAAMMGG.HHMM` (ora di Roma).

## [0.6.0] · build 20261117.1350

Pronta per TestFlight.

### Aggiunto
- Team Apple Developer in `project.yml`, per archiviare e caricare su App Store Connect senza scegliere il Team a mano
- `strumenti/nuova-build.sh`: numero di build nuovo a ogni caricamento
- README: come distribuire con TestFlight
- **Icona dell'app** (logo di Argo, 1024 px senza trasparenza): senza, App Store Connect rifiuta il caricamento

## [0.6.0] · build 20261117.1135

Ponte con Argo sul computer: niente più AirDrop a mano.

### Aggiunto
- **Argo sul computer** (Impostazioni): collegamento inquadrando il QR di Argo desktop (*Incontri › 📱 Collega iPhone…*) con il lettore di sistema (VisionKit)
- Canale **HTTPS in rete locale con pinning** del certificato del computer; segreto nel Portachiavi (solo questo dispositivo)
- **Sincronizzazione automatica** quando Argo torna in primo piano o tiri giù l'elenco: anagrafe voci scelta sul computer giù, incontri trascritti su (mai durante l'elaborazione)
- In ogni incontro: **Invia ad Argo sul computer** e indicazione «inviato»; nell'elenco l'icona del computer sugli incontri consegnati
- Opzione «Elimina dall'iPhone dopo l'invio»
- Protocollo documentato in argo-ai `docs/PONTE.md`

### Modificato
- Una relazione rifatta sul telefono fa ripartire l'invio (il computer conserva il lavoro già fatto sullo stesso incontro)

## [0.5.0] · build 20261117.1110

L'anagrafe voci di Argo desktop arriva sull'iPhone.

### Aggiunto
- Import dei file `.argovoci` esportati da Argo desktop (*Voci › 📱 Per iPhone…*): AirDrop › «Apri con Argo», oppure *Impostazioni › Anagrafe voci › Importa da file*
- Negli incontri le voci note prendono il loro nome; abbinamento uno-a-uno come `voci_core.abbina` del desktop, con la soglia del desktop
- Il profilo voce personale partecipa allo stesso abbinamento (nessun doppione se ha lo stesso nome di una voce dell'anagrafe)
- Impostazioni: elenco delle voci importate, aggiornamento, eliminazione

### Privacy
- Anagrafe salvata con protezione completa del file; il file ricevuto via AirDrop viene cancellato dopo l'import; le impronte non entrano mai nel pacchetto Argo

## [0.4.1] · build 20261117.1059

### Modificato
- Profilo voce e riconoscimento usano lo stesso modello della divisione delle voci (pipeline offline FluidAudio): impronta del profilo con `embedSpans`, impronte dei parlanti da `speakerDatabase`. Niente secondo modello da scaricare, confronto più coerente e più veloce (nessun ricalcolo sull'audio)

### Corretto
- API FluidAudio verificate sul sorgente (la guida citava un `extractEmbedding` inesistente)
- Kit `prova-impronte`: stesso metodo dell'app e messaggi di errore di compilazione leggibili

## [0.4.0] · build 20261117.1035

### Aggiunto
- **Profilo voce**: in *Impostazioni › La mia voce* registri una volta 20 secondi leggendo un testo; Argo ne calcola l'impronta (FluidAudio) e cancella subito l'audio
- Negli incontri la voce più simile al profilo (somiglianza coseno ≥ 0,55) prende il tuo nome, le altre restano «Parlante N»
- La relazione sa chi registra e non lo mette tra i contatti

### Privacy
- L'impronta vocale è un dato biometrico: salvata solo sull'iPhone con protezione completa del file, mai inclusa nel pacchetto Argo, eliminabile dalle impostazioni

## [0.3.1] · build 20261117.1000

### Corretto
- Scattare una foto metteva in pausa la registrazione: la fotocamera di sistema prendeva il controllo dell'audio. Ora Argo usa una fotocamera interna (solo video, `automaticallyConfiguresApplicationAudioSession = false`) e la registrazione continua

### Aggiunto
- Più foto di fila senza uscire dalla fotocamera (es. fronte e retro del biglietto)
- Timer della registrazione visibile mentre scatti; ogni foto prende il secondo esatto dello scatto

## [0.3.0] · build 20261117.0941

Taccuino da fiera: voci, foto e pacchetto per il Mac.

### Aggiunto
- **Foto durante la registrazione**: pulsante fotocamera nella schermata di registrazione; ogni foto viene agganciata al secondo esatto della conversazione
- **Testo delle foto** (OCR con Apple Vision, sul dispositivo) con riconoscimento di telefoni, email, siti e indirizzi
- **Divisione delle voci** sul dispositivo con FluidAudio (pipeline pyannote in CoreML); i parlanti si possono rinominare («Io», «Mario Rossi»)
- Trascrizione come **cronologia**: frasi con parlante e minuto, intercalate alle foto
- Relazione con **contatti** (nome, azienda, ruolo, email, telefono, interesse), ricavati soprattutto dai biglietti da visita
- **Pacchetto Argo** (.zip con `sessione.json`, `relazione.md` e foto) da passare al Mac via AirDrop o File; formato documentato in `docs/FORMATO-PACCHETTO.md`
- Pulsante «Rifai la relazione» dopo aver dato un nome ai parlanti

### Modificato
- Le istruzioni del modello spiegano parlanti e foto, per una relazione che colleghi ciò che si dice a ciò che si fotografa
- Informativa aggiornata: consenso dell'interlocutore, divisione per voci, eliminazione dell'audio
- Cancellare una sessione elimina anche le sue foto

## [0.2.0] · build 20261117.0905

Compatibile anche con gli iPhone senza Apple Intelligence.

### Aggiunto
- Motore del verbale a scelta in *Impostazioni › Verbale*: Automatico, Apple Intelligence, Il mio Mac (Ollama), Nessuno
- Motore «Il mio Mac»: il verbale viene scritto da Ollama sul Mac in rete locale, con output JSON strutturato, contesto da 8K e riduzione a blocchi
- Prova di connessione al Mac ed elenco dei modelli Ollama installati
- Il verbale indica quale motore l'ha scritto
- Pulsante «Crea il verbale» per le sessioni già trascritte (es. dopo aver collegato il Mac)

### Modificato
- Senza un motore disponibile non è più un errore: resta la trascrizione con un avviso informativo
- Informativa aggiornata: il verbale può essere scritto dal Mac in rete locale, mai in cloud

### Corretto
- «Riprova» non compare più quando riprovare non cambierebbe nulla

## [0.1.0] · build 20261116.2204

Prima versione: MVP nativo, tutto sul dispositivo.

### Aggiunto
- Registrazione dal microfono (AAC mono 16 kHz), anche a schermo bloccato, con pausa, misuratore di livello e gestione delle telefonate in arrivo
- Informativa da confermare prima di ogni registrazione
- Trascrizione on-device con `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26), con marche temporali e download automatico del modello della lingua
- Verbale con Foundation Models (Apple Intelligence) e guided generation: titolo, riassunto, punti chiave, azioni con responsabile e scadenza
- Riduzione a blocchi per le trascrizioni più lunghe del contesto del modello
- Opzione «Elimina l'audio dopo la trascrizione» (attiva di default)
- Importazione di file audio da Memo Vocali e File
- Condivisione del verbale in Markdown
- Impostazioni: lingua della riunione (IT, EN, DE, FR, ES), privacy, stato di Apple Intelligence
- Progetto generato con XcodeGen (`project.yml`)
