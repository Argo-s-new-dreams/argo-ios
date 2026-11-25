import AVFoundation
import Speech

/// Il canale audio di Argo Live: microfono e voce di Argo passano dallo stesso motore audio con l'elaborazione
/// vocale di iOS attiva (cancellazione dell'eco). Così il microfono resta aperto anche mentre Argo parla e,
/// se parli, lo puoi interrompere senza che Argo senta sé stesso. L'audio non viene mai salvato.
final class CanaleAudioLive {
    private let motore = AVAudioEngine()
    private let lettore = AVAudioPlayerNode()
    private let sintetizzatore = AVSpeechSynthesizer()
    private let formatoVoce = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var convertitoreVoce: AVAudioConverter?
    private let coda = DispatchQueue(label: "blog.argosnewdreams.argo.live.voce")
    private var inRiproduzione = 0

    /// Chiamate sul thread principale.
    var allaPrimaVoce: (() -> Void)?
    var allaFineVoce: (() -> Void)?

    var parla: Bool { coda.sync { inRiproduzione > 0 } }

    func avvia(formatoAnalisi: AVAudioFormat, continuazione: AsyncStream<AnalyzerInput>.Continuation) throws {
        let sessione = AVAudioSession.sharedInstance()
        try sessione.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try sessione.setActive(true)

        let ingresso = motore.inputNode
        try ingresso.setVoiceProcessingEnabled(true)
        motore.attach(lettore)
        motore.connect(lettore, to: motore.mainMixerNode, format: formatoVoce)

        let formatoIngresso = ingresso.outputFormat(forBus: 0)
        guard let convertitore = AVAudioConverter(from: formatoIngresso, to: formatoAnalisi) else {
            throw ErroreLive.formatoAudio
        }
        let rapporto = formatoAnalisi.sampleRate / formatoIngresso.sampleRate
        ingresso.installTap(onBus: 0, bufferSize: 2048, format: formatoIngresso) { buffer, _ in
            let capacita = AVAudioFrameCount(Double(buffer.frameLength) * rapporto) + 1024
            guard let uscita = AVAudioPCMBuffer(pcmFormat: formatoAnalisi, frameCapacity: capacita) else { return }
            var fornito = false
            var errore: NSError?
            convertitore.convert(to: uscita, error: &errore) { _, stato in
                if fornito {
                    stato.pointee = .noDataNow
                    return nil
                }
                fornito = true
                stato.pointee = .haveData
                return buffer
            }
            if errore == nil, uscita.frameLength > 0 {
                continuazione.yield(AnalyzerInput(buffer: uscita))
            }
        }
        motore.prepare()
        try motore.start()
    }

    func ferma() {
        zittisci()
        motore.inputNode.removeTap(onBus: 0)
        motore.stop()
        try? motore.inputNode.setVoiceProcessingEnabled(false)
        if motore.attachedNodes.contains(lettore) { motore.detach(lettore) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Legge una frase: la voce di iOS scrive l'audio a pezzi e lo suoniamo dal nostro motore audio.
    func pronuncia(_ testo: String, lingua: String) {
        let pulito = testo
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pulito.isEmpty else { return }
        let frase = AVSpeechUtterance(string: pulito)
        frase.voice = AVSpeechSynthesisVoice(language: lingua)
        sintetizzatore.write(frase) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0,
                  let convertito = self.converti(pcm) else { return }
            let primo = self.coda.sync { () -> Bool in
                self.inRiproduzione += 1
                return self.inRiproduzione == 1
            }
            self.lettore.scheduleBuffer(convertito) { [weak self] in self?.bufferFinito() }
            if !self.lettore.isPlaying { self.lettore.play() }
            if primo { DispatchQueue.main.async { self.allaPrimaVoce?() } }
        }
    }

    func zittisci() {
        sintetizzatore.stopSpeaking(at: .immediate)
        lettore.stop()
        coda.sync { inRiproduzione = 0 }
    }

    private func bufferFinito() {
        let finito = coda.sync { () -> Bool in
            guard inRiproduzione > 0 else { return false }
            inRiproduzione -= 1
            return inRiproduzione == 0
        }
        if finito { DispatchQueue.main.async { self.allaFineVoce?() } }
    }

    private func converti(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format == formatoVoce { return pcm }
        if convertitoreVoce?.inputFormat != pcm.format {
            convertitoreVoce = AVAudioConverter(from: pcm.format, to: formatoVoce)
        }
        guard let convertitoreVoce else { return nil }
        let capacita = AVAudioFrameCount(Double(pcm.frameLength) * formatoVoce.sampleRate / pcm.format.sampleRate) + 1024
        guard let uscita = AVAudioPCMBuffer(pcmFormat: formatoVoce, frameCapacity: capacita) else { return nil }
        var fornito = false
        var errore: NSError?
        convertitoreVoce.convert(to: uscita, error: &errore) { _, stato in
            if fornito {
                stato.pointee = .noDataNow
                return nil
            }
            fornito = true
            stato.pointee = .haveData
            return pcm
        }
        return errore == nil && uscita.frameLength > 0 ? uscita : nil
    }

    /// Permessi di microfono e riconoscimento vocale.
    static func autorizzato() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuazione in
            SFSpeechRecognizer.requestAuthorization { stato in
                continuazione.resume(returning: stato == .authorized)
            }
        }
    }
}

/// Divide il testo che arriva a pezzi in frasi da leggere.
struct DivisoreFrasi {
    private var resto = ""

    mutating func aggiungi(_ pezzo: String) -> [String] {
        resto += pezzo
        var frasi: [String] = []
        while let fine = resto.firstIndex(where: { ".!?;:\n".contains($0) }) {
            let dopo = resto.index(after: fine)
            let frase = String(resto[..<dopo]).trimmingCharacters(in: .whitespacesAndNewlines)
            resto = String(resto[dopo...])
            if frase.count > 1 { frasi.append(frase) }
        }
        return frasi
    }

    mutating func svuota() -> String {
        defer { resto = "" }
        return resto.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
