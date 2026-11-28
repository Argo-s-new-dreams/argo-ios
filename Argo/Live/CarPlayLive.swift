import CarPlay
import UIKit

/// Argo Live in CarPlay (categoria «voice-based conversational», iOS 26.4): appena apri Argo sullo schermo
/// dell'auto parte la conversazione a voce. Una sola schermata, quella vocale di Apple, che dice cosa sta facendo
/// Argo; niente testo delle risposte sullo schermo, come chiedono le regole di CarPlay. La conversazione è la
/// stessa del telefono (SessioneLive.condivisa). Si chiude con il pulsante «Chiudi», a voce («Chiudi Argo»,
/// «Basta così»…), passando a un'altra app di CarPlay o scollegando l'auto: così il microfono si libera e l'auto
/// esce dalla modalità telefono. Tornando su Argo riparte da sola; «Riprendi» la riapre.
/// Solo nelle build di prova (Laboratorio) e con il modello già scaricato sul telefono.
@MainActor
final class CarPlayLive: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaccia: CPInterfaceController?
    private var voce: CPVoiceControlTemplate?
    private var osservazione: Task<Void, Never>?
    private var sessione: SessioneLive { SessioneLive.condivisa }

    private static let stati: [(String, String, String)] = [
        ("spenta", "Conversazione chiusa", "pause.circle"),
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

    /// Passi a un'altra app di CarPlay (Mappe, Musica…): chiudo, così l'auto torna all'audio normale.
    func sceneDidEnterBackground(_ scene: UIScene) {
        guard interfaccia != nil else { return }
        Task { await SessioneLive.condivisa.chiudi() }
    }

    /// Torni su Argo in CarPlay: la conversazione riparte da sola, come all'apertura.
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard voce != nil, sessione.fase == .spenta else { return }
        Task { await riprendi() }
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
        if sessione.fase == .spenta { await riprendi() }
    }

    private func riprendi() async {
        let preferenze = UserDefaults.standard
        let lingua = preferenze.string(forKey: "liveLingua") ?? LiveView.linguaPredefinita
        let gpu = preferenze.object(forKey: "liveGPU") as? Bool ?? true
        await sessione.inizia(lingua: lingua, gpu: gpu)
    }

    /// In alto a destra: «Chiudi» mentre la conversazione è aperta, «Riprendi» quando è chiusa.
    private func aggiornaPulsanti(aperta: Bool) {
        guard let voce else { return }
        let pulsante: CPBarButton
        if aperta {
            pulsante = CPBarButton(title: String(localized: "Chiudi")) { _ in
                Task { await SessioneLive.condivisa.chiudi() }
            }
        } else {
            pulsante = CPBarButton(title: String(localized: "Riprendi")) { [weak self] _ in
                Task { await self?.riprendi() }
            }
        }
        voce.trailingNavigationBarButtons = [pulsante]
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
        aggiornaPulsanti(aperta: !(id == "spenta" || id == "errore"))
    }
}
