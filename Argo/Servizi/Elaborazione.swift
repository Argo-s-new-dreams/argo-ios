import Foundation

/// Pipeline completa: audio → trascrizione → verbale. Tutto sul dispositivo.
@MainActor
enum Elaborazione {

    static func esegui(
        _ sessione: Sessione,
        eliminaAudioDopo: Bool,
        fase: @escaping @MainActor (String) -> Void
    ) async {
        sessione.messaggioErrore = nil
        do {
            if sessione.trascrizione.isEmpty {
                guard let url = sessione.urlAudio else {
                    throw ErroreElaborazione.audioMancante
                }
                sessione.stato = .inTrascrizione
                sessione.trascrizione = try await Trascrittore.trascrivi(
                    file: url, lingua: sessione.lingua, fase: fase
                )
                sessione.stato = .trascritta
                // Come la modalità Live del Mac: trascritto l'audio, lo si elimina.
                if eliminaAudioDopo { sessione.eliminaAudio() }
            }

            if let avviso = Verbalista.messaggioIndisponibilita {
                sessione.messaggioErrore = avviso
                return
            }

            let verbale = try await Verbalista.genera(da: sessione.trascrizione, fase: fase)
            sessione.titolo = verbale.titolo
            sessione.riassunto = verbale.riassunto
            sessione.puntiChiave = verbale.puntiChiave
            sessione.azioni = verbale.azioni.map {
                Azione(descrizione: $0.descrizione, responsabile: $0.responsabile, scadenza: $0.scadenza)
            }
            sessione.stato = .completata
        } catch {
            sessione.stato = sessione.trascrizione.isEmpty ? .errore : .trascritta
            sessione.messaggioErrore = error.localizedDescription
        }
    }
}

enum ErroreElaborazione: LocalizedError {
    case audioMancante
    var errorDescription: String? { "Il file audio di questa sessione non è più disponibile." }
}
