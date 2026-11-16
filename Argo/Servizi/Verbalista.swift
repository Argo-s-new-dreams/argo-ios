import Foundation
import FoundationModels

/// Struttura che il modello on-device compila direttamente (guided generation).
@Generable
struct VerbaleGenerato {
    @Guide(description: "Titolo breve e concreto della riunione, al massimo 8 parole")
    var titolo: String

    @Guide(description: "Riassunto della riunione in 3-5 frasi")
    var riassunto: String

    @Guide(description: "I punti chiave discussi, al massimo 8, una frase ciascuno")
    var puntiChiave: [String]

    @Guide(description: "Le azioni da fare emerse dalla riunione; lista vuota se non ce ne sono")
    var azioni: [AzioneGenerata]
}

@Generable
struct AzioneGenerata {
    @Guide(description: "Cosa va fatto, come frase all'imperativo")
    var descrizione: String

    @Guide(description: "Chi se ne occupa, solo se viene citato esplicitamente")
    var responsabile: String?

    @Guide(description: "La scadenza, solo se viene citata, con le parole usate nella riunione")
    var scadenza: String?
}

/// Crea il verbale con il modello di Apple Intelligence sul dispositivo.
/// La finestra di contesto è piccola (circa 4.000 token): le trascrizioni lunghe
/// vengono prima riassunte a blocchi, poi unite.
enum Verbalista {

    /// Caratteri per blocco: prudente, per lasciare spazio a istruzioni e risposta.
    private static let caratteriPerBlocco = 5_000

    private static let istruzioniNote = """
    Sei l'assistente che prende appunti in una riunione di lavoro.
    Ricevi una parte di trascrizione. Scrivi appunti sintetici e fedeli: decisioni,
    problemi, numeri, nomi, azioni da fare con responsabili e scadenze.
    Non inventare nulla. Rispondi nella stessa lingua della trascrizione.
    """

    private static let istruzioniVerbale = """
    Sei l'assistente che redige il verbale di una riunione di lavoro.
    Usa solo le informazioni presenti nel testo ricevuto, senza inventare
    nomi, date o decisioni. Rispondi nella stessa lingua del testo.
    """

    static var disponibilita: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var messaggioIndisponibilita: String? {
        switch disponibilita {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Questo iPhone non supporta Apple Intelligence: avrai la trascrizione, ma non il verbale automatico."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Attiva Apple Intelligence in Impostazioni per generare il verbale."
        case .unavailable(.modelNotReady):
            return "Il modello di Apple Intelligence si sta ancora scaricando. Riprova tra poco."
        case .unavailable:
            return "Apple Intelligence non è disponibile in questo momento."
        }
    }

    static func genera(
        da trascrizione: String,
        fase: @escaping @MainActor (String) -> Void
    ) async throws -> VerbaleGenerato {
        var materiale = trascrizione
        var giro = 1

        // Riduzione a blocchi finché il testo non entra in una sola richiesta.
        while materiale.count > caratteriPerBlocco && giro <= 3 {
            let blocchi = dividi(materiale, massimo: caratteriPerBlocco)
            var note: [String] = []
            for (indice, blocco) in blocchi.enumerated() {
                await fase("Prendo appunti · parte \(indice + 1) di \(blocchi.count)…")
                let sessione = LanguageModelSession(instructions: istruzioniNote)
                let risposta = try await sessione.respond(to: "Parte di trascrizione:\n\n\(blocco)")
                note.append(risposta.content)
            }
            materiale = note.joined(separator: "\n\n")
            giro += 1
        }

        await fase("Scrivo il verbale…")
        let sessione = LanguageModelSession(instructions: istruzioniVerbale)
        let risposta = try await sessione.respond(
            to: "Redigi il verbale a partire da questo testo:\n\n\(materiale)",
            generating: VerbaleGenerato.self
        )
        return risposta.content
    }

    /// Divide per righe, senza spezzare le frasi a metà.
    private static func dividi(_ testo: String, massimo: Int) -> [String] {
        var blocchi: [String] = []
        var corrente = ""
        for riga in testo.split(separator: "\n", omittingEmptySubsequences: false) {
            if corrente.count + riga.count + 1 > massimo, !corrente.isEmpty {
                blocchi.append(corrente)
                corrente = ""
            }
            if riga.count > massimo {
                // riga lunghissima (raro): taglio netto
                var resto = Substring(riga)
                while !resto.isEmpty {
                    blocchi.append(String(resto.prefix(massimo)))
                    resto = resto.dropFirst(massimo)
                }
            } else {
                corrente += (corrente.isEmpty ? "" : "\n") + riga
            }
        }
        if !corrente.isEmpty { blocchi.append(corrente) }
        return blocchi
    }
}
