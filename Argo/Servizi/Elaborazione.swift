import Foundation

/// Pipeline completa, tutto sull'iPhone salvo la relazione se affidata al Mac:
/// audio → trascrizione → parlanti → audio eliminato → testo delle foto → relazione.
@MainActor
enum Elaborazione {

    /// Sessioni in elaborazione: il Ponte non le invia finché non hanno finito.
    static private(set) var inCorso = Set<UUID>()

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
            sessione.messaggioErrore = error.localizedDescription
        }
        sessione.avviso = avvisi.isEmpty ? nil : avvisi.joined(separator: "\n")
    }
}

enum ErroreElaborazione: LocalizedError {
    case audioMancante
    var errorDescription: String? { "Il file audio di questa sessione non è più disponibile." }
}
