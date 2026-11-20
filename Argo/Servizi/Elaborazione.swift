import Foundation
import Observation
import UIKit

/// Fase in corso di ogni sessione in elaborazione: la schermata dell'incontro la mostra anche se la riapri
/// a lavoro avviato.
@MainActor
@Observable
final class FasiElaborazione {
    var valori: [UUID: String] = [:]
}

/// Pipeline completa, tutto sull'iPhone salvo la relazione se affidata al Mac:
/// audio → trascrizione → parlanti → audio eliminato → testo delle foto → relazione.
@MainActor
enum Elaborazione {

    /// Sessioni in elaborazione: il Ponte non le invia finché non hanno finito.
    static private(set) var inCorso = Set<UUID>()
    static let fasi = FasiElaborazione()
    private static var tempoInBackground: UIBackgroundTaskIdentifier = .invalid

    /// Avvia l'elaborazione in un Task che NON dipende dalla schermata: prima partiva dal `.task` della vista e,
    /// uscendo dall'incontro, SwiftUI la annullava a metà (Swift.CancellationError su un incontro di un'ora).
    /// Finché lavora, lo schermo non si spegne da solo e, se l'app va in background, iOS concede ancora
    /// qualche momento per chiudere il passo in corso.
    static func avvia(_ sessione: Sessione, eliminaAudioDopo: Bool) {
        guard !inCorso.contains(sessione.id) else { return }
        let id = sessione.id
        inCorso.insert(id)
        fasi.valori[id] = "Preparo…"
        tieniSveglio()
        Task { @MainActor in
            await esegui(sessione, eliminaAudioDopo: eliminaAudioDopo) { fasi.valori[id] = $0 }
            fasi.valori[id] = nil
            lasciaDormire()
        }
    }

    private static func tieniSveglio() {
        UIApplication.shared.isIdleTimerDisabled = true
        guard tempoInBackground == .invalid else { return }
        tempoInBackground = UIApplication.shared.beginBackgroundTask(withName: "Argo · elaborazione") {
            // Tempo finito: iOS sospende l'app. Il lavoro riprende quando torni su Argo.
            MainActor.assumeIsolated { chiudiTempoInBackground() }
        }
    }

    private static func lasciaDormire() {
        guard inCorso.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        chiudiTempoInBackground()
    }

    private static func chiudiTempoInBackground() {
        guard tempoInBackground != .invalid else { return }
        UIApplication.shared.endBackgroundTask(tempoInBackground)
        tempoInBackground = .invalid
    }

    /// Annullamento (Task annullato, richiesta di rete annullata): non è un errore del passo, è un'interruzione.
    static func eAnnullamento(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    static func esegui(
        _ sessione: Sessione,
        eliminaAudioDopo: Bool,
        fase: @escaping @MainActor (String) -> Void
    ) async {
        inCorso.insert(sessione.id)
        defer { inCorso.remove(sessione.id) }
        sessione.messaggioErrore = nil
        sessione.avviso = nil
        var avvisi: [String] = []
        do {
            // 1 · Trascrizione e parlanti (servono entrambi l'audio)
            if !sessione.haTrascrizione {
                guard let originale = sessione.urlAudio else { throw ErroreElaborazione.audioMancante }
                sessione.stato = .inTrascrizione
                // File che iOS non apre (registrazione interrotta): si prova a recuperarlo in una copia temporanea.
                let url = try await LettoreAudio.leggibile(originale)
                defer { LettoreAudio.elimina(url, originale: originale) }
                var segmenti = try await Trascrittore.trascrivi(file: url, lingua: sessione.lingua, fase: fase)

                var impronte: [String: [Float]] = [:]
                do {
                    let voci = try await Diarizzatore.turni(file: url, fase: fase)
                    impronte = voci.impronte
                    segmenti = Diarizzatore.assegna(voci.turni, a: segmenti)
                } catch {
                    // Interrotto: si ferma tutto e l'audio resta, così i parlanti si possono rifare.
                    if eAnnullamento(error) { throw error }
                    avvisi.append("Parlanti non riconosciuti (\(error.localizedDescription)). La trascrizione c'è comunque.")
                }

                // Chi è chi: anagrafe voci di Argo desktop + il tuo profilo voce, abbinati uno a uno.
                let profilo = ArchivioVoce.carica()
                let anagrafe = ArchivioAnagrafe.carica()
                if !impronte.isEmpty, profilo != nil || anagrafe != nil {
                    var candidati = (anagrafe?.voci ?? []).map { (nome: $0.nome, impronta: $0.impronta) }
                    if let profilo { candidati.append((profilo.nome, profilo.impronta)) }
                    let soglia = Float(anagrafe?.soglia ?? Double(RiconoscitoreVoce.soglia))
                    let riconosciuti = RiconoscitoreVoce.abbina(impronte, candidati: candidati, soglia: soglia)
                    for (parlante, nome) in riconosciuti { sessione.nomiParlanti[parlante] = nome }
                    if let profilo, !riconosciuti.values.contains(profilo.nome) {
                        avvisi.append("Non ho riconosciuto la tua voce in questo incontro: puoi dare i nomi a mano in Partecipanti.")
                    }
                }

                sessione.segmenti = segmenti
                sessione.trascrizione = segmenti.map(\.testo).joined(separator: " ")
                sessione.stato = .trascritta
                // Nessuna registrazione resta sul telefono.
                if eliminaAudioDopo { sessione.eliminaAudio() }
            }

            // 2 · Testo delle foto (OCR sul dispositivo)
            for indice in sessione.foto.indices where !sessione.foto[indice].letta {
                fase("Leggo la foto \(indice + 1) di \(sessione.foto.count)…")
                let lettura = await LettoreFoto.leggi(sessione.foto[indice].url)
                sessione.foto[indice].testoOCR = lettura.testo
                sessione.foto[indice].riferimenti = lettura.riferimenti
                sessione.foto[indice].letta = true
            }

            // 3 · Relazione
            switch Verbalista.risolvi() {
            case .nonDisponibile(let motivo):
                avvisi.append(motivo)
            case .pronto(let motore):
                var testo = sessione.testoCompleto
                if let profilo = ArchivioVoce.carica(), sessione.nomiParlanti.values.contains(profilo.nome) {
                    testo = "Chi registra è «\(profilo.nome)»: non va incluso nei contatti.\n\n" + testo
                }
                let relazione = try await motore.genera(da: testo, fase: fase)
                sessione.titolo = relazione.titolo
                sessione.riassunto = relazione.riassunto
                sessione.puntiChiave = relazione.puntiChiave
                sessione.azioni = relazione.azioni.map {
                    Azione(descrizione: $0.descrizione, responsabile: $0.responsabile, scadenza: $0.scadenza)
                }
                sessione.contatti = relazione.contatti.map {
                    Contatto(nome: $0.nome, azienda: $0.azienda, ruolo: $0.ruolo,
                             email: $0.email, telefono: $0.telefono, note: $0.note)
                }
                sessione.motoreVerbale = motore.nome
                sessione.stato = .completata
                // Relazione nuova o rifatta: va (ri)consegnata ad Argo sul computer.
                sessione.inviataAdArgo = nil
            }
        } catch {
            sessione.stato = sessione.haTrascrizione ? .trascritta : .errore
            if eAnnullamento(error) {
                sessione.messaggioErrore = sessione.haTrascrizione
                    ? "Relazione interrotta prima della fine. Premi «Crea la relazione» per riprendere."
                    : "Elaborazione interrotta prima della fine. L'audio è ancora sul telefono: premi «Trascrivi e crea la relazione» per riprendere."
            } else {
                sessione.messaggioErrore = error.localizedDescription
            }
        }
        sessione.avviso = avvisi.isEmpty ? nil : avvisi.joined(separator: "\n")
    }
}

enum ErroreElaborazione: LocalizedError {
    case audioMancante
    var errorDescription: String? { "Il file audio di questa sessione non è più disponibile." }
}
