import CarPlay
import UIKit

/// Argo Live in CarPlay (categoria «voice-based conversational», iOS 26.4): appena apri Argo sullo schermo
/// dell'auto parte la conversazione a voce. Una sola schermata, quella vocale di Apple, che dice cosa sta facendo
/// Argo; niente testo delle risposte sullo schermo, come chiedono le regole di CarPlay. La conversazione è la
/// stessa del telefono (SessioneLive.condivisa): si chiude quando chiudi Argo in CarPlay o scolleghi l'auto.
/// Solo nelle build di prova (Laboratorio) e con il modello già scaricato sul telefono.
@MainActor
final class CarPlayLive: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaccia: CPInterfaceController?
    private var voce: CPVoiceControlTemplate?
    private var osservazione: Task<Void, Never>?
    private var sessione: SessioneLive { SessioneLive.condivisa }

    private static let stati: [(String, String, String)] = [
        ("spenta", "Argo Live è in pausa", "pause.circle"),
        ("carico", "Preparo Argo…", "hourglass"),
        ("ascolto", "Ti ascolto", "waveform"),
        ("sento", "Ti sento", "waveform.badge.mic"),
        ("penso", "Ci penso…", "ellipsis"),
        ("parlo", "Argo risponde", "speaker.wave.2"),
        ("errore", "Qualcosa non va: riprova dal telefono", "exclamationmark.triangle"),
    ]

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interfaccia = interfaceController
        Task { await avvia() }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        osservazione?.cancel()
        osservazione = nil
        voce = nil
        interfaccia = nil
        Task { await SessioneLive.condivisa.chiudi() }
    }

    private func avvia() async {
        guard await Laboratorio.attivo() else {
            mostra("Argo Live non è disponibile in questa versione di Argo.")
            return
        }
        guard ModelloLive.presente else {
            mostra("Prima scarica il modello sul telefono: Parla con Argo › Scarica.")
            return
        }
        let stati = Self.stati.map { id, titolo, simbolo in
            CPVoiceControlState(identifier: id, titleVariants: [titolo], image: UIImage(systemName: simbolo),
                                repeats: id == "ascolto" || id == "penso")
        }
        let modello = CPVoiceControlTemplate(voiceControlStates: stati)
        voce = modello
        interfaccia?.setRootTemplate(modello, animated: false, completion: nil)
        osserva()
        if sessione.fase == .spenta {
            let preferenze = UserDefaults.standard
            let lingua = preferenze.string(forKey: "liveLingua") ?? LiveView.linguaPredefinita
            let gpu = preferenze.object(forKey: "liveGPU") as? Bool ?? true
            await sessione.inizia(lingua: lingua, gpu: gpu)
        }
    }

    /// Un messaggio fisso sulla schermata vocale (quando Live non può partire).
    private func mostra(_ testo: String) {
        let stato = CPVoiceControlState(identifier: "messaggio", titleVariants: [testo],
                                        image: UIImage(systemName: "info.circle"), repeats: false)
        let modello = CPVoiceControlTemplate(voiceControlStates: [stato])
        voce = modello
        interfaccia?.setRootTemplate(modello, animated: false, completion: nil)
    }

    private func osserva() {
        osservazione?.cancel()
        let sessione = self.sessione
        osservazione = Task { [weak self] in
            while !Task.isCancelled {
                self?.aggiornaStato()
                await withCheckedContinuation { (fatto: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = sessione.fase
                        _ = sessione.errore
                    } onChange: {
                        fatto.resume()
                    }
                }
            }
        }
    }

    private func aggiornaStato() {
        let id: String
        if sessione.errore != nil && sessione.fase == .spenta {
            id = "errore"
        } else {
            switch sessione.fase {
            case .spenta: id = "spenta"
            case .carico: id = "carico"
            case .inAscolto: id = "ascolto"
            case .sentendo: id = "sento"
            case .penso: id = "penso"
            case .parlo: id = "parlo"
            }
        }
        voce?.activateVoiceControlState(withIdentifier: id)
    }
}
