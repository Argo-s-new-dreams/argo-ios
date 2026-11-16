import AVFoundation
import Observation

/// Registra dal microfono in AAC mono 16 kHz (adatto alla trascrizione, file leggeri).
/// Continua anche a schermo bloccato grazie a UIBackgroundModes = audio.
@MainActor
@Observable
final class Registratore {
    private(set) var staRegistrando = false
    private(set) var inPausa = false
    private(set) var durata: TimeInterval = 0
    /// Livello del microfono normalizzato 0…1, per il misuratore.
    private(set) var livello: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var osservatoreInterruzioni: NSObjectProtocol?
    private(set) var nomeFile: String?

    static func chiediPermessoMicrofono() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func avvia() throws {
        let sessioneAudio = AVAudioSession.sharedInstance()
        try sessioneAudio.setCategory(.record, mode: .default)
        try sessioneAudio.setActive(true)

        let nome = "argo-\(UUID().uuidString).m4a"
        let url = Archivio.cartellaAudio.appending(path: nome)
        let impostazioni: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let nuovo = try AVAudioRecorder(url: url, settings: impostazioni)
        nuovo.isMeteringEnabled = true
        guard nuovo.record() else { throw ErroreRegistrazione.avvioFallito }

        recorder = nuovo
        nomeFile = nome
        staRegistrando = true
        inPausa = false
        durata = 0
        avviaTimer()
        osservaInterruzioni()
    }

    func pausa() {
        recorder?.pause()
        inPausa = true
    }

    func riprendi() {
        recorder?.record()
        inPausa = false
    }

    /// Ferma e restituisce nome file e durata.
    func ferma() -> (nomeFile: String, durata: TimeInterval)? {
        guard let recorder, let nomeFile else { return nil }
        let durataFinale = recorder.currentTime > 0 ? recorder.currentTime : durata
        recorder.stop()
        pulisci()
        return (nomeFile, durataFinale)
    }

    func annulla() {
        recorder?.stop()
        recorder?.deleteRecording()
        pulisci()
    }

    private func pulisci() {
        timer?.invalidate()
        timer = nil
        if let osservatoreInterruzioni {
            NotificationCenter.default.removeObserver(osservatoreInterruzioni)
        }
        osservatoreInterruzioni = nil
        recorder = nil
        nomeFile = nil
        staRegistrando = false
        inPausa = false
        livello = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func avviaTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.aggiorna() }
        }
    }

    private func aggiorna() {
        guard let recorder else { return }
        durata = recorder.currentTime
        recorder.updateMeters()
        // da dB (-60…0) a 0…1
        let db = max(-60, recorder.averagePower(forChannel: 0))
        livello = inPausa ? 0 : (db + 60) / 60
    }

    /// Una telefonata in arrivo mette in pausa; alla fine dell'interruzione si riprende.
    private func osservaInterruzioni() {
        osservatoreInterruzioni = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notifica in
            guard let valore = notifica.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let tipo = AVAudioSession.InterruptionType(rawValue: valore) else { return }
            Task { @MainActor in
                switch tipo {
                case .began: self?.inPausa = true
                case .ended:
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self?.riprendi()
                @unknown default: break
                }
            }
        }
    }
}

enum ErroreRegistrazione: LocalizedError {
    case avvioFallito
    var errorDescription: String? { "Non riesco ad avviare la registrazione." }
}
