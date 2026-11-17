# Prova di compatibilità delle impronte vocali

Verifica se le impronte dell'anagrafe voci di **Argo desktop** (pyannote community-1 via WhisperX)
e quelle di **Argo per iPhone** (FluidAudio) si possono confrontare direttamente.

## Cosa serve
- Argo desktop installato (`~/whisperx-env`, con token Hugging Face già configurato)
- Xcode (per `swift build`)
- 2-3 audio di **una sola persona** ciascuno, 20-30 secondi: ideale due tuoi (registrati in momenti diversi) e uno di un'altra persona, con il suo consenso

## Uso
```bash
cd strumenti/prova-impronte
./prova.sh ~/Desktop/io_1.m4a ~/Desktop/io_2.m4a ~/Desktop/altro.m4a
```

Il risultato finisce in `risultato.txt`. Gli audio convertiti restano in una cartella temporanea, cancellata alla fine.

## Come leggere il verdetto
- **Compatibili** (somiglianza ≥ 0,80 sullo stesso audio): l'iPhone usa direttamente l'anagrafe del desktop.
- **Parzialmente** (0,50–0,80): stesso spazio con deriva, quindi un'impronta per motore oppure una soglia tarata.
- **Incompatibili** (< 0,50): un'impronta per motore; quella per l'iPhone la calcola il Mac con FluidAudio.
