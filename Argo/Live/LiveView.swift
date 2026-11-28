import CoreMedia
import Darwin
import os
import Speech
import StoreKit
import SwiftUI

/// Laboratorio: funzioni di prova visibili solo nelle build Debug (Xcode) e TestFlight, mai sull'App Store.
enum Laboratorio {
    static func attivo() async -> Bool {
#if DEBUG
        return true
#else
        guard let esito = try? await AppTransaction.shared else { return false }
        switch esito {
        case .verified(let transazione), .unverified(let transazione, _):
            return transazione.environment != .production
        }
#endif
    }
}

/// Memoria dell'app (phys_footprint, come le misure di LiteRT-LM su iOS) e memoria ancora disponibile.
enum MemoriaLive {
    static var usataMB: Int {
        var info = task_vm_info_data_t()
        var conteggio = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let esito = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(conteggio)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &conteggio)
            }
        }
        return esito == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : 0
    }

    static var disponibileMB: Int { Int(os_proc_available_memory() / 1_048_576) }
}

struct ScambioLive: Identifiable {
    let id = UUID()
    let domanda: String
    var risposta: String
}

struct MisureLive {
    var caricamento: Double?
    var primaParola: Double?
    var primaVoce: Double?
    var prefill: Double?
    var decode: Double?
    var tokenRisposta: Int?
    var memoriaUsata = 0
    var memoriaDisponibile = 0
}

/// Conversazione continua: Argo ascolta sempre, capisce che hai finito da una pausa, risponde a voce e,
/// se parli mentre risponde, si zittisce e ti ascolta.
@MainActor
@Observable
final class SessioneLive {
    enum StatoModello: Equatable { case assente, scarico(Double), verifico, pronto, errore(String) }
    enum Fase: Equatable { case spenta, carico, inAscolto, sentendo, penso, parlo }

    /// Pausa che chiude il turno.
    static let pausaFineTurno: TimeInterval = 0.9
    /// Parole che servono per interrompere Argo mentre parla.
    static let paroleInterruzione = 2

    var statoModello: StatoModello = ModelloLive.presente ? .pronto : .assente
    var fase: Fase = .spenta
    var scambi: [ScambioLive] = []
    var misure = MisureLive()
    var errore: String?
    var ascoltato = ""

    private let motore = MotoreLive()
    private var canale: CanaleAudioLive?
    private var analizzatore: SpeechAnalyzer?
    private var continuazione: AsyncStream<AnalyzerInput>.Continuation?
    private var raccolta: Task<Void, Never>?
    private var sorveglianza: Task<Void, Never>?
    private var rispostaInCorso: Task<Void, Never>?
    private var scaricatore: ScaricatoreLive?

    private var lingua = "it-IT"
    private var testoFinale = ""
    private var testoVolatile = ""
    private var ultimoCambio = Date.distantPast
    private var fineAudioTurno = CMTime.zero
    private var taglio = CMTime.zero
    private var fineTurno = Date()
    private var generazioneFinita = true

    private var testoTurno: String {
        [testoFinale, testoVolatile].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Una sola conversazione per tutta l'app: la stessa sul telefono e in CarPlay.
    static let condivisa = SessioneLive()

    init() { aggiornaMemoria() }

    func aggiornaMemoria() {
        misure.memoriaUsata = MemoriaLive.usataMB
        misure.memoriaDisponibile = MemoriaLive.disponibileMB
    }

    // MARK: Modello

    func scaricaModello() {
        guard ModelloLive.spazioSufficiente else {
            errore = "Spazio insufficiente: servono circa \(ModelloLive.megabyte + 1000) MB liberi."
            return
        }
        errore = nil
        statoModello = .scarico(0)
        let scaricatore = ScaricatoreLive(
            avanzamento: { [weak self] frazione in self?.statoModello = .scarico(frazione) },
            fine: { [weak self] esito in self?.concludiScarico(esito) }
        )
        self.scaricatore = scaricatore
        scaricatore.avvia()
    }

    func annullaScarico() {
        scaricatore?.annulla()
        scaricatore = nil
        statoModello = .assente
    }

    private func concludiScarico(_ esito: Result<URL, Error>) {
        scaricatore = nil
        switch esito {
        case .failure(let errore):
            if (errore as NSError).code == NSURLErrorCancelled { return }
            statoModello = .errore(errore.localizedDescription)
        case .success(let temporaneo):
            statoModello = .verifico
            Task.detached(priority: .userInitiated) {
                let valido = (try? ModelloLive.verifica(temporaneo)) ?? false
                await MainActor.run {
                    if valido {
                        do {
                            try ModelloLive.installa(da: temporaneo)
                            self.statoModello = .pronto
                        } catch {
                            self.statoModello = .errore(error.localizedDescription)
                        }
                    } else {
                        try? FileManager.default.removeItem(at: temporaneo)
                        self.statoModello = .errore(ErroreLive.hashErrato.localizedDescription)
                    }
                }
            }
        }
    }

    func eliminaModello() async {
        await chiudi()
        motore.scarica()
        ModelloLive.elimina()
        statoModello = .assente
        misure = MisureLive()
        aggiornaMemoria()
    }

    func cambiaMotore() async {
        await chiudi()
        motore.scarica()
        misure.caricamento = nil
        aggiornaMemoria()
    }

    // MARK: Conversazione

    func inizia(lingua: String, gpu: Bool) async {
        errore = nil
        self.lingua = lingua
        do {
            if !motore.caricato || motore.gpu != gpu {
                fase = .carico
                misure.caricamento = try await motore.carica(gpu: gpu)
                aggiornaMemoria()
            }
            try await motore.nuovaConversazione(lingua: lingua)
            try await avviaAscolto()
            fase = .inAscolto
        } catch {
            await chiudi()
            self.errore = error.localizedDescription
        }
    }

    func chiudi() async {
        sorveglianza?.cancel()
        sorveglianza = nil
        interrompiRisposta()
        canale?.ferma()
        canale = nil
        continuazione?.finish()
        continuazione = nil
        await analizzatore?.cancelAndFinishNow()
        analizzatore = nil
        raccolta?.cancel()
        raccolta = nil
        testoFinale = ""
        testoVolatile = ""
        ascoltato = ""
        fase = .spenta
        aggiornaMemoria()
    }

    func nuovaConversazione() async {
        let attiva = fase != .spenta
        interrompiRisposta()
        scambi = []
        try? await motore.nuovaConversazione(lingua: lingua)
        if attiva { fase = .inAscolto }
    }

    /// Zittisce Argo senza chiudere la conversazione.
    func zitto() {
        interrompiRisposta()
        if fase == .parlo || fase == .penso { fase = .inAscolto }
    }

    private func avviaAscolto() async throws {
        guard await CanaleAudioLive.autorizzato() else { throw ErroreLive.nonAutorizzato }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: lingua)) else {
            throw ErroreLive.linguaNonSupportata(lingua)
        }
        let trascrittore = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                             reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        if let richiesta = try await AssetInventory.assetInstallationRequest(supporting: [trascrittore]) {
            try await richiesta.downloadAndInstall()
        }
        guard let formato = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [trascrittore]) else {
            throw ErroreLive.formatoAudio
        }
        let analizzatore = SpeechAnalyzer(modules: [trascrittore])
        let (sequenza, continuazione) = AsyncStream<AnalyzerInput>.makeStream()
        self.analizzatore = analizzatore
        self.continuazione = continuazione
        taglio = .zero
        fineAudioTurno = .zero

        raccolta = Task { [weak self] in
            do {
                for try await risultato in trascrittore.results {
                    self?.ricevi(risultato)
                }
            } catch {}
        }
        try await analizzatore.start(inputSequence: sequenza)

        let canale = CanaleAudioLive()
        canale.allaPrimaVoce = { [weak self] in
            guard let self, self.misure.primaVoce == nil else { return }
            self.misure.primaVoce = Date().timeIntervalSince(self.fineTurno)
        }
        canale.allaFineVoce = { [weak self] in
            guard let self, self.generazioneFinita, self.fase == .parlo else { return }
            self.fase = .inAscolto
        }
        try canale.avvia(formatoAnalisi: formato, continuazione: continuazione)
        self.canale = canale

        sorveglianza = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                self?.controllaFineTurno()
            }
        }
    }

    private func ricevi(_ risultato: SpeechTranscriber.Result) {
        // Pezzi di audio già usati in un turno precedente (arrivano dopo, come risultato definitivo): li ignoro.
        if CMTimeCompare(risultato.range.end, taglio) <= 0 { return }
        let testo = String(risultato.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if risultato.isFinal {
            if !testo.isEmpty { testoFinale += (testoFinale.isEmpty ? "" : " ") + testo }
            testoVolatile = ""
        } else {
            testoVolatile = testo
        }
        guard !testo.isEmpty else { return }
        ultimoCambio = Date()
        if risultato.range.end.isValid { fineAudioTurno = CMTimeMaximum(fineAudioTurno, risultato.range.end) }
        ascoltato = testoTurno

        switch fase {
        case .inAscolto:
            fase = .sentendo
        case .penso, .parlo:
            let parole = testoTurno.split(whereSeparator: \.isWhitespace).count
            if parole >= Self.paroleInterruzione {
                interrompiRisposta()
                fase = .sentendo
            }
        default:
            break
        }
    }

    private func controllaFineTurno() {
        guard fase == .sentendo, !testoTurno.isEmpty,
              Date().timeIntervalSince(ultimoCambio) >= Self.pausaFineTurno else { return }
        let domanda = testoTurno
        taglio = fineAudioTurno
        testoFinale = ""
        testoVolatile = ""
        ascoltato = ""
        fineTurno = Date()
        if Self.comandoChiusura(domanda) {
            Task { await chiudi() }
            return
        }
        rispondi(domanda)
    }

    /// Frasi brevi che chiudono la conversazione a voce (anche in auto, senza toccare niente).
    static let frasiChiusura: Set<String> = [
        "chiudi", "chiudi argo", "chiudi la conversazione", "fine", "fine conversazione", "basta", "basta così",
        "basta grazie", "stop", "stop argo", "ciao argo", "arrivederci", "a posto così", "abbiamo finito",
        "close", "goodbye", "bye", "bye argo", "goodbye argo", "end conversation", "stop conversation", "that's all",
        "adiós", "adiós argo", "termina", "terminar", "para", "cierra", "fin",
        "tschüss", "tschüss argo", "beenden", "schluss", "stopp", "auf wiedersehen", "das war's",
    ]

    static func comandoChiusura(_ testo: String) -> Bool {
        let pulito = testo.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'")))
            .joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard pulito.split(separator: " ").count <= 4 else { return false }
        return frasiChiusura.contains(pulito)
    }

    private func rispondi(_ domanda: String) {
        scambi.append(ScambioLive(domanda: domanda, risposta: ""))
        let indice = scambi.count - 1
        misure.primaParola = nil
        misure.primaVoce = nil
        generazioneFinita = false
        fase = .penso
        let precedente = rispostaInCorso
        rispostaInCorso = Task { [weak self] in
            await precedente?.value
            guard let self else { return }
            var divisore = DivisoreFrasi()
            do {
                for try await pezzo in try await self.motore.rispondi(domanda, lingua: self.lingua) {
                    if Task.isCancelled { break }
                    if self.misure.primaParola == nil {
                        self.misure.primaParola = Date().timeIntervalSince(self.fineTurno)
                    }
                    self.scambi[indice].risposta += pezzo
                    for frase in divisore.aggiungi(pezzo) {
                        self.canale?.pronuncia(frase, lingua: self.lingua)
                        if self.fase == .penso { self.fase = .parlo }
                    }
                }
                if !Task.isCancelled {
                    let ultima = divisore.svuota()
                    if !ultima.isEmpty {
                        self.canale?.pronuncia(ultima, lingua: self.lingua)
                        if self.fase == .penso { self.fase = .parlo }
                    }
                    if let info = self.motore.misure() {
                        self.misure.prefill = info.lastPrefillTokensPerSecond
                        self.misure.decode = info.lastDecodeTokensPerSecond
                        self.misure.tokenRisposta = info.lastDecodeTokenCount
                    }
                }
            } catch {
                if !Task.isCancelled { self.errore = error.localizedDescription }
            }
            self.generazioneFinita = true
            if self.fase == .penso || (self.fase == .parlo && !(self.canale?.parla ?? false)) {
                self.fase = .inAscolto
            }
            self.aggiornaMemoria()
        }
    }

    private func interrompiRisposta() {
        rispostaInCorso?.cancel()
        motore.interrompi()
        canale?.zittisci()
        generazioneFinita = true
    }
}

/// Prova di Argo Live (laboratorio): conversazione continua a voce, tutta sull'iPhone.
/// SpeechAnalyzer ascolta, Gemma 4 E2B risponde, la voce di iOS legge. Mostra i tempi di ogni risposta.
struct LiveView: View {
    @State private var sessione = SessioneLive.condivisa
    @AppStorage("liveLingua") private var lingua = LiveView.linguaPredefinita
    @AppStorage("liveGPU") private var gpu = true
    @State private var confermaScarico = false
    @State private var confermaElimina = false

    static let lingue = [("it-IT", "Italiano"), ("en-US", "English"), ("es-ES", "Español"), ("de-DE", "Deutsch")]

    static var linguaPredefinita: String {
        let codice = Locale.current.language.languageCode?.identifier ?? "it"
        return lingue.first { $0.0.hasPrefix(codice) }?.0 ?? "it-IT"
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: "Prova di laboratorio, tutta sull'iPhone. Premi «Inizia conversazione» e parla normalmente: quando fai una pausa Argo risponde a voce. Se parli mentre risponde, si zittisce e ti ascolta.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            sezioneModello

            if sessione.statoModello == .pronto {
                sezioneConversazione
                sezioneMisure
                sezioneImpostazioni
            }

            if let errore = sessione.errore {
                Section {
                    Text(errore).foregroundStyle(StileArgo.avviso)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Argo Live · prova"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await sessione.chiudi() } }
        .alert(Text(verbatim: "Scaricare il modello?"), isPresented: $confermaScarico) {
            Button { sessione.scaricaModello() } label: { Text(verbatim: "Scarica") }
            Button(role: .cancel) {} label: { Text(verbatim: "Annulla") }
        } message: {
            Text(verbatim: "Gemma 4 E2B (Google, Apache 2.0) da Hugging Face: circa \(ModelloLive.megabyte) MB. Meglio con il Wi-Fi e l'app aperta. Viene scaricato una volta e resta sul telefono.")
        }
        .alert(Text(verbatim: "Eliminare il modello?"), isPresented: $confermaElimina) {
            Button(role: .destructive) { Task { await sessione.eliminaModello() } } label: { Text(verbatim: "Elimina") }
            Button(role: .cancel) {} label: { Text(verbatim: "Annulla") }
        } message: {
            Text(verbatim: "Libera circa \(ModelloLive.megabyte) MB. Per usare di nuovo Live andrà riscaricato.")
        }
    }

    // MARK: Sezioni

    private var sezioneModello: some View {
        Section {
            switch sessione.statoModello {
            case .assente:
                Button { confermaScarico = true } label: {
                    Label { Text(verbatim: "Scarica Gemma 4 E2B (\(ModelloLive.megabyte) MB)") } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            case .scarico(let frazione):
                VStack(alignment: .leading) {
                    ProgressView(value: frazione)
                    Text(verbatim: "Scarico… \(Int(frazione * 100))%").font(.footnote)
                }
                Button(role: .cancel) { sessione.annullaScarico() } label: { Text(verbatim: "Annulla") }
            case .verifico:
                HStack {
                    ProgressView()
                    Text(verbatim: "Controllo il file (SHA-256)…")
                }
            case .pronto:
                Label { Text(verbatim: "Gemma 4 E2B pronto sul telefono") } icon: {
                    Image(systemName: "checkmark.circle").foregroundStyle(StileArgo.ok)
                }
            case .errore(let messaggio):
                Text(messaggio).foregroundStyle(StileArgo.avviso)
                Button { confermaScarico = true } label: { Text(verbatim: "Riprova a scaricare") }
            }
        } header: {
            Text(verbatim: "Modello")
        }
    }

    private var sezioneConversazione: some View {
        Section {
            VStack(spacing: 10) {
                indicatore
                Text(verbatim: descrizioneFase)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !sessione.ascoltato.isEmpty {
                    Text(sessione.ascoltato)
                        .font(.subheadline.italic())
                        .multilineTextAlignment(.center)
                }
                pulsanti
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            ForEach(sessione.scambi.reversed()) { scambio in
                VStack(alignment: .leading, spacing: 6) {
                    Text(scambio.domanda).font(.subheadline.weight(.semibold))
                    Text(scambio.risposta.isEmpty ? "…" : scambio.risposta).font(.subheadline)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(verbatim: "Conversazione")
        }
    }

    private var indicatore: some View {
        let (simbolo, colore): (String, Color) = switch sessione.fase {
        case .spenta: ("waveform.slash", .secondary)
        case .carico: ("hourglass", .secondary)
        case .inAscolto: ("ear", StileArgo.ok)
        case .sentendo: ("waveform", StileArgo.ok)
        case .penso: ("ellipsis.bubble", StileArgo.avviso)
        case .parlo: ("speaker.wave.2.fill", StileArgo.parlanti[0])
        }
        return Image(systemName: simbolo)
            .font(.system(size: 44))
            .foregroundStyle(colore)
            .symbolEffect(.pulse, isActive: sessione.fase == .sentendo || sessione.fase == .parlo)
            .frame(height: 56)
    }

    @ViewBuilder
    private var pulsanti: some View {
        switch sessione.fase {
        case .spenta:
            Button { Task { await sessione.inizia(lingua: lingua, gpu: gpu) } } label: {
                Label { Text(verbatim: "Inizia conversazione") } icon: { Image(systemName: "mic.fill") }
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        case .carico:
            ProgressView()
        default:
            HStack(spacing: 12) {
                if sessione.fase == .parlo || sessione.fase == .penso {
                    Button { sessione.zitto() } label: {
                        Label { Text(verbatim: "Zitto") } icon: { Image(systemName: "hand.raised.fill") }
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { Task { await sessione.chiudi() } } label: {
                    Label { Text(verbatim: "Chiudi") } icon: { Image(systemName: "xmark") }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var descrizioneFase: String {
        switch sessione.fase {
        case .spenta: sessione.scambi.isEmpty ? "Premi «Inizia conversazione» e parla." : "Conversazione chiusa."
        case .carico: "Carico il modello in memoria (la prima volta ci vuole di più)…"
        case .inAscolto: "Ti ascolto."
        case .sentendo: "Ti sento… quando fai una pausa rispondo."
        case .penso: "Penso…"
        case .parlo: "Rispondo… parla pure per interrompermi."
        }
    }

    private var sezioneMisure: some View {
        Section {
            riga("Caricamento del modello", sessione.misure.caricamento.map { secondi($0) })
            riga("Prima parola scritta", sessione.misure.primaParola.map { secondi($0) })
            riga("Prima parola detta", sessione.misure.primaVoce.map { secondi($0) })
            riga("Prefill", sessione.misure.prefill.map { String(format: "%.0f token/s", $0) })
            riga("Generazione", sessione.misure.decode.map { String(format: "%.1f token/s", $0) })
            riga("Token della risposta", sessione.misure.tokenRisposta.map { "\($0)" })
            riga("Memoria di Argo", "\(sessione.misure.memoriaUsata) MB")
            riga("Memoria ancora disponibile", "\(sessione.misure.memoriaDisponibile) MB")
        } header: {
            Text(verbatim: "Misure dell'ultima risposta")
        } footer: {
            Text(verbatim: "Tempi misurati dalla fine della pausa (\(String(format: "%.1f", SessioneLive.pausaFineTurno)) s dopo l'ultima parola). Motore: \(gpu ? "GPU" : "CPU, 4 thread") · Gemma 4 E2B · contesto 2048 token")
        }
    }

    private var sezioneImpostazioni: some View {
        Section {
            Picker(selection: $lingua) {
                ForEach(Self.lingue, id: \.0) { voce in Text(verbatim: voce.1).tag(voce.0) }
            } label: { Text(verbatim: "Lingua della conversazione") }
            .disabled(sessione.fase != .spenta)

            Toggle(isOn: $gpu) { Text(verbatim: "Usa la GPU") }
                .disabled(sessione.fase != .spenta)
                .onChange(of: gpu) { _, _ in Task { await sessione.cambiaMotore() } }

            Button { Task { await sessione.nuovaConversazione() } } label: {
                Text(verbatim: "Nuova conversazione (dimentica le domande)")
            }
            Button(role: .destructive) { confermaElimina = true } label: {
                Text(verbatim: "Elimina il modello (\(ModelloLive.megabyte) MB)")
            }
        } header: {
            Text(verbatim: "Prova")
        } footer: {
            Text(verbatim: "Lingua e motore si cambiano a conversazione chiusa. GPU: più veloce, usa più memoria. CPU: più lenta, più leggera.")
        }
    }

    private func riga(_ titolo: String, _ valore: String?) -> some View {
        LabeledContent {
            Text(valore ?? "—").monospacedDigit()
        } label: {
            Text(titolo)
        }
    }

    private func secondi(_ valore: Double) -> String { String(format: "%.2f s", valore) }
}
