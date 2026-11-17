# Changelog

Tutte le modifiche rilevanti di Argo per iPhone.
Versioni: `MARKETING_VERSION` (semver) + build `AAAAMMGG.HHMM` (ora di Roma).

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
