import Foundation

/// Pipeline completa: audio → trascrizione (sempre sull'iPhone) → verbale (motore scelto).
@MainActor
enum Elaborazione {

    static func esegui(
        _ sessione: Sessione,
        eliminaAudioDopo: Bool,
        fase: @escaping @MainActor (String) -> Void
    ) async {
        sessione.messaggioErrore = nil
        sessione.avviso = nil
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

            switch Verbalista.risolvi() {
            case .nonDisponibile(let motivo):
                // Non è un errore: la trascrizione c'è, il verbale si potrà creare dopo.
                sessione.avviso = motivo
            case .pronto(let motore):
                let verbale = try await motore.genera(da: sessione.trascrizione, fase: fase)
                sessione.titolo = verbale.titolo
                sessione.riassunto = verbale.riassunto
                sessione.puntiChiave = verbale.puntiChiave
                sessione.azioni = verbale.azioni.map {
                    Azione(descrizione: $0.descrizione, responsabile: $0.responsabile, scadenza: $0.scadenza)
                }
                sessione.motoreVerbale = motore.nome
                sessione.stato = .completata
            }
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
