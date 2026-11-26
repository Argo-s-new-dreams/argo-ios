# Changelog

Tutte le modifiche rilevanti di Argo per iPhone.
Versioni: `MARKETING_VERSION` (semver) + build `AAAAMMGG.HHMM` (ora di Roma).

## [1.2] · build (al prossimo invio)

Prima prova di Argo Live: parli con Argo a voce, senza tasti, e Argo risponde a voce, tutto sull'iPhone. Solo per i tester.

### Aggiunto
- **Laboratorio › Argo Live · prova** in Impostazioni, visibile solo nelle build di prova (TestFlight e Xcode), mai nell'App Store.
  - **Conversazione continua**: premi **Inizia conversazione** e parla normalmente. Argo ascolta sempre, capisce che hai finito da una pausa (0,9 secondi), risponde a voce e torna ad ascoltare. **Zitto** lo ferma, **Chiudi** chiude il microfono.
  - **Puoi interromperlo**: se parli mentre risponde (bastano due parole), si zittisce e ti ascolta. Il microfono resta aperto con la cancellazione dell'eco di iOS, così Argo non sente sé stesso.
  - La trascrizione è di iOS (SpeechAnalyzer, sul dispositivo), la risposta la scrive **Gemma 4 E2B** di Google con il motore **LiteRT-LM**, e la legge la voce di iOS una frase alla volta mentre il modello scrive le successive.
  - Il modello (circa 2,6 GB, Apache 2.0) si scarica una volta da Hugging Face solo se lo chiedi, con controllo SHA-256. Resta sul telefono, escluso dal backup di iCloud. Si elimina dalla stessa schermata.
  - Lingue della conversazione: italiano, inglese, spagnolo e tedesco. Motore GPU (più veloce) o CPU (più leggero).
  - Le **misure** di ogni domanda: caricamento del modello, trascrizione, prima parola scritta e detta, token al secondo, memoria usata e disponibile.
- Nella schermata principale, accanto a **Registra**, il pulsante **Parla con Argo** apre subito Argo Live (solo nelle build di prova). Resta anche in Impostazioni › Laboratorio.
- **Argo Live in CarPlay** (prima versione, da provare nel simulatore CarPlay di Xcode): apri Argo sullo schermo dell'auto e la conversazione parte subito a voce, con la schermata vocale di Apple (Ti ascolto, Ci penso, Argo risponde) e senza testo delle risposte sullo schermo. Serve iOS 26.4 e l'autorizzazione CarPlay che Apple concede app per app: finché non arriva, sull'auto vera Argo non compare.
- **«Ehi Siri, registra con Argo»** (anche in auto): apre Argo sulla registrazione; l'informativa ai partecipanti si conferma come sempre sul telefono.
- Licenze di LiteRT-LM e Gemma 4 in Impostazioni › Licenze e riconoscimenti e in `LICENZE-TERZE-PARTI.md`.

### Note
- È un prototipo per misurare il telefono vero: niente incontri come memoria, niente cloud. I testi della schermata di prova sono solo in italiano.
- La conversazione resta solo in memoria: chiudendo la schermata si perde. L'audio non viene mai salvato.
- Serve un iPhone con almeno 6 GB di memoria (per esempio iPhone 13 Pro, 14 o successivi).
- Il prototipo era sul ramo `live-prototipo`; dalla 1.2 è nel ramo principale e arriva ai tester interni di TestFlight.

### Da provare
- **Parla con Argo** (o Impostazioni › Laboratorio › Argo Live · prova) › Scarica (meglio con il Wi-Fi), poi **Inizia conversazione** e parla come al telefono
- Interrompere Argo mentre risponde: deve zittirsi e ascoltarti; con l'altoparlante, controllare che non risponda a sé stesso
- Annotare le misure della seconda domanda (la prima include il caricamento del modello)
- Ripetere con «Usa la GPU» spento e confrontare
- Provare inglese, spagnolo e tedesco
- Con le cuffie Bluetooth: Argo risponde nelle cuffie?

## [1.1.1] · build 20261125.2043

L'iPhone ritrova Argo sul computer anche su un'altra rete o in un altro posto, senza rifare l'abbinamento.

### Corretto
- **Ritrovarsi su un'altra rete**: l'iPhone salvava gli indirizzi del computer (che cambiano da una rete all'altra) e un nome che poteva contenere il dominio della rete. Ora, se gli indirizzi salvati non rispondono, cerca il computer in rete locale con **Bonjour** (servizio `_argoponte._tcp`) per il suo id, e a ogni sincronizzazione riceve indirizzi e porta aggiornati. Serve Argo desktop dalla 20261125.1224; con le versioni di prima resta il comportamento vecchio.
- La sicurezza non cambia: l'iPhone accetta solo il computer con l'impronta del certificato ricevuta dal QR e il segreto nel Portachiavi. Non si usa il MAC, che l'iPhone non può leggere e che cambia da una rete all'altra (indirizzo Wi‑Fi privato).

### Da provare
- Collega l'iPhone a casa, poi porta Mac e iPhone su un'altra rete (ufficio o hotspot): con Argo aperto sul Mac, Impostazioni › Argo sul computer › **Sincronizza ora** deve riuscire senza inquadrare di nuovo il QR.
- Gli abbinamenti fatti prima ritrovano il computer per nome; dopo la prima sincronizzazione riuscita imparano anche l'id.

## [1.1] · build (al prossimo invio)

Argo parla quattro lingue: italiano, inglese, spagnolo e tedesco. Gli incontri lunghi non si interrompono più se esci dalla schermata, e in Impostazioni trovi licenze e riconoscimenti.

### Aggiunto
- **Interfaccia in italiano, inglese, spagnolo e tedesco**: schermate, avvisi, errori, fasi dell'elaborazione, testo condiviso della relazione e descrizioni dei permessi (microfono, fotocamera, rete locale, riconoscimento vocale). Argo segue la lingua dell'iPhone; per sceglierne un'altra solo per Argo: Impostazioni di iOS › Argo › Lingua (in Argo › Impostazioni › Lingua dell'app c'è il collegamento). Con l'iPhone in un'altra lingua Argo resta in italiano.
- La **lingua della riunione** resta una scelta a parte; i nomi delle lingue ora sono scritti nella lingua dell'app.
- Testi in `Argo/Localizable.xcstrings` e `Argo/InfoPlist.xcstrings`. La GitHub Action **Compila** ora esporta anche le traduzioni e si ferma se un testo non è tradotto (`strumenti/controlla-traduzioni.py`).
- **Licenze e riconoscimenti** in Impostazioni › Informazioni: FluidAudio (Apache 2.0) con i componenti che include, e i modelli pyannote per la divisione delle voci (CC BY 4.0, convertiti in Core ML da Fluid Inference). Lo stesso elenco è in `LICENZE-TERZE-PARTI.md`.

### Corretto
- **Incontri lunghi interrotti a metà** («Impossibile completare l'operazione. (Errore Swift.CancellationError 1)»). L'elaborazione partiva dalla schermata dell'incontro: uscendo, iOS la annullava. I parlanti restavano senza nome, l'audio veniva cancellato e la relazione non partiva. Ora:
  - l'elaborazione continua anche se torni all'elenco;
  - lo schermo resta acceso finché Argo lavora;
  - se Argo viene interrotto lo stesso, l'audio resta sul telefono e un messaggio chiaro dice come riprendere.

### Note
- Le traduzioni sono una prima versione da rileggere.
- Il **verbale** scritto da Apple Intelligence o dal Mac resta per ora in italiano: le istruzioni al modello non sono cambiate.
- I nomi dei menu di Argo sul computer citati in inglese, spagnolo e tedesco («Meetings › Connect iPhone…») saranno giusti quando anche Argo desktop avrà le quattro lingue.

### Da provare
- Impostazioni di iOS › Argo › Lingua › English (poi Español, Deutsch): schermate, avvisi e richiesta del microfono nella nuova lingua; poi torna all'italiano
- Registra un incontro di almeno 10 minuti, poi torna subito all'elenco: trascrizione, parlanti e relazione devono arrivare lo stesso. Lo schermo resta acceso finché Argo lavora
- Impostazioni › Informazioni › Licenze e riconoscimenti: il testo si apre e si scorre fino in fondo

## [1.0] · build 20261120.830

Prima versione per l'App Store, approvata e pubblicata il 20/11/2026. Se sul computer spegni il riconoscimento delle voci, anche l'iPhone smette di usarle.

### Modificato
- **Voci allineate al computer**: Argo sul computer (dalla 20261119.1720) tiene il riconoscimento delle voci spento finché non lo attivi, con il consenso di ogni persona. Quando è spento, alla sincronizzazione con il Ponte l'iPhone elimina le voci che aveva scaricato e i parlanti restano «Parlante 1, 2…».

### Corretto
- Le miniature delle foto (durante la registrazione e nell'incontro) non debordano più su quelle accanto: ognuna resta nel suo riquadro
- Impostazioni: dichiarato l'uso di SwiftData, che la compilazione segnalava come avviso (nessun effetto per chi usa l'app)

### Sviluppo
- **Modalità vetrina** per gli screenshot dell'App Store: `strumenti/screenshot-appstore.sh` compila Argo per il simulatore iPhone 6,9" e fotografa sei schermate con incontri, persone e aziende inventati. Esiste solo nelle build Debug: nella versione per TestFlight e App Store non c'è.

### Da provare
- Con il riconoscimento delle voci spento sul computer, sincronizza: le voci spariscono dall'iPhone e i nuovi incontri usano «Parlante 1, 2…»
- L'aggiornamento arriva da TestFlight senza fare nulla e gli incontri già presenti restano al loro posto

## [0.6.3] · build 20261119.0750

Gli incontri non si perdono più senza preavviso.

### Aggiunto
- **Avviso in cima alla lista** finché ci sono incontri solo su questo iPhone (non ancora arrivati ad Argo sul computer): quanti sono, quanti vanno prima trascritti e il pulsante **Invia ora ad Argo sul computer**. Se il computer non è collegato, dice dove collegarlo.
- **README**: cosa fare prima di installare una nuova versione, e perché passare dal *Personal Team* al team a pagamento obbliga a eliminare l'app (e con lei gli incontri non inviati).

## [0.6.2] · build 20261118.2045

Registrazioni che non si rovinano più.

### Corretto
- **«Impossibile completare l'operazione (Errore com.apple.coreaudio.avfaudio 2003334207)»**: iOS non riusciva ad aprire il file audio (`'wht?'`). Le registrazioni erano in `.m4a` (AAC), leggibili solo se si chiudono bene: l'indice dei pacchetti si scrive alla fine.
- **Nuovo formato di registrazione**: PCM 16 bit mono 16 kHz in `.caf`, che resta leggibile fino all'ultimo secondo registrato anche se la registrazione si interrompe. Circa 115 MB per ora, solo fino alla trascrizione: poi l'audio viene eliminato come prima.
- **Recupero dei file già registrati**: se iOS non apre l'audio, Argo prova a decodificarlo con un secondo lettore (`AVAssetReader`) in una copia temporanea, eliminata subito dopo. Se nemmeno così si apre, compare un messaggio chiaro al posto del codice di errore Apple.

## [0.6.1] · build 20261117.2025

Manutenzione UX: stesso «Stile Argo» del computer, meno sorprese.

### Modificato
- **Colori dello Stile Argo**: accento terracotta al posto del blu di sistema, salvia per «fatto» e ocra per gli avvisi; i **parlanti hanno gli stessi colori** che su Argo sul computer
- Si parla di **incontri** come su Argo desktop (elenco vuoto: «Nessun incontro», con l'invito a toccare Registra)
- In un incontro **«Trascrivi e crea la relazione» sta in alto** finché la relazione non c'è; «Rifai la relazione» resta in fondo
- «Inviato ad Argo sul computer» con l'icona del computer, non più con quella del cloud: nessun cloud di mezzo
- **Conferma prima di eliminare** un incontro (swipe) e il profilo voce
- VoiceOver: etichette chiare per Pausa/Riprendi e Ferma

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
