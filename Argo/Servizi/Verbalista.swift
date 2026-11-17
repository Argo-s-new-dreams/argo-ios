import Foundation
import FoundationModels

/// Struttura del verbale. Con Apple Intelligence il modello la compila direttamente
/// (guided generation); con Ollama arriva come JSON e viene decodificata.
@Generable
struct VerbaleGenerato: Codable {
    @Guide(description: "Titolo breve e concreto della riunione, al massimo 8 parole")
    var titolo: String

    @Guide(description: "Riassunto della riunione in 3-5 frasi")
    var riassunto: String

    @Guide(description: "I punti chiave discussi, al massimo 8, una frase ciascuno")
    var puntiChiave: [String]

    @Guide(description: "Le azioni da fare emerse dalla riunione; lista vuota se non ce ne sono")
    var azioni: [AzioneGenerata]

    @Guide(description: "Le persone incontrate (esclusa la persona che registra), con i dati presi soprattutto dalle foto di biglietti da visita; lista vuota se nessuna")
    var contatti: [ContattoGenerato]
}

@Generable
struct ContattoGenerato: Codable {
    @Guide(description: "Nome e cognome")
    var nome: String
    @Guide(description: "Azienda, se nota")
    var azienda: String?
    @Guide(description: "Ruolo o qualifica, se noto")
    var ruolo: String?
    @Guide(description: "Email, solo se letta in una foto o detta esplicitamente")
    var email: String?
    @Guide(description: "Telefono, solo se letto in una foto o detto esplicitamente")
    var telefono: String?
    @Guide(description: "Cosa interessa a questa persona o cosa ha chiesto, in una frase")
    var note: String?
}

@Generable
struct AzioneGenerata: Codable {
    @Guide(description: "Cosa va fatto, come frase all'imperativo")
    var descrizione: String

    @Guide(description: "Chi se ne occupa, solo se viene citato esplicitamente")
    var responsabile: String?

    @Guide(description: "La scadenza, solo se viene citata, con le parole usate nella riunione")
    var scadenza: String?
}

// MARK: - Scelta del motore

/// Chi scrive il verbale.
enum SceltaMotore: String, CaseIterable, Identifiable {
    case automatico, apple, mac, nessuno
    var id: String { rawValue }

    var nome: String {
        switch self {
        case .automatico: "Automatico"
        case .apple: "Apple Intelligence (iPhone)"
        case .mac: "Il mio Mac (Ollama)"
        case .nessuno: "Nessuno, solo trascrizione"
        }
    }
}

/// Esito della scelta: un motore pronto oppure un avviso da mostrare.
enum MotoreRisolto {
    case pronto(any MotoreVerbale)
    case nonDisponibile(String)
}

protocol MotoreVerbale: Sendable {
    var nome: String { get }
    func genera(da trascrizione: String, fase: @escaping @MainActor (String) -> Void) async throws -> VerbaleGenerato
}

enum Verbalista {

    static let istruzioniNote = """
    Sei l'assistente che prende appunti in un incontro di lavoro (riunione o fiera).
    Ricevi una parte di trascrizione: ogni riga ha il minuto e chi parla.
    Le righe «📷 FOTO» contengono il testo letto da una foto scattata in quel momento
    (biglietto da visita, brochure, documento, cartellino di un prodotto).
    Scrivi appunti sintetici e fedeli: chi è chi, aziende, prodotti, richieste, numeri,
    decisioni, azioni da fare. Conserva nomi, email e telefoni letti nelle foto.
    Non inventare nulla. Rispondi nella stessa lingua della trascrizione.
    """

    static let istruzioniVerbale = """
    Sei l'assistente che redige la relazione di un incontro di lavoro (riunione o fiera).
    Ogni riga del testo ha il minuto e chi parla. Le righe «📷 FOTO» sono testi letti da
    foto scattate durante l'incontro: usale per dare un nome, un'azienda e dei recapiti
    alle persone, e collega ciò che si vede nelle foto a ciò che viene detto in quel momento.
    Usa solo le informazioni presenti, senza inventare nomi, date, recapiti o decisioni.
    Rispondi nella stessa lingua del testo.
    """

    static var appleDisponibile: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Perché Apple Intelligence non è utilizzabile (nil se lo è).
    static var motivoAppleNonDisponibile: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Questo iPhone non supporta Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence non è attiva (Impostazioni › Apple Intelligence e Siri)."
        case .unavailable(.modelNotReady):
            return "Il modello di Apple Intelligence si sta ancora scaricando."
        case .unavailable:
            return "Apple Intelligence non è disponibile in questo momento."
        }
    }

    /// Sceglie il motore in base alle impostazioni.
    static func risolvi() -> MotoreRisolto {
        let impostazioni = UserDefaults.standard
        let scelta = SceltaMotore(rawValue: impostazioni.string(forKey: "motore") ?? "") ?? .automatico
        let mac = MotoreOllama.daImpostazioni()

        switch scelta {
        case .nessuno:
            return .nonDisponibile("Verbale disattivato nelle impostazioni: c'è solo la trascrizione.")
        case .apple:
            if appleDisponibile { return .pronto(MotoreApple()) }
            return .nonDisponibile((motivoAppleNonDisponibile ?? "") + " Puoi usare il Mac in Impostazioni › Verbale.")
        case .mac:
            if let mac { return .pronto(mac) }
            return .nonDisponibile("Indica l'indirizzo del Mac in Impostazioni › Verbale.")
        case .automatico:
            if appleDisponibile { return .pronto(MotoreApple()) }
            if let mac { return .pronto(mac) }
            return .nonDisponibile((motivoAppleNonDisponibile ?? "") +
                " Per avere il verbale, collega il tuo Mac con Ollama in Impostazioni › Verbale.")
        }
    }

    /// Riduce la trascrizione a blocchi finché entra in una sola richiesta.
    static func riduci(
        _ testo: String,
        massimo: Int,
        fase: @escaping @MainActor (String) -> Void,
        appunti: (String) async throws -> String
    ) async throws -> String {
        var materiale = testo
        var giro = 1
        while materiale.count > massimo && giro <= 3 {
            let blocchi = dividi(materiale, massimo: massimo)
            var note: [String] = []
            for (indice, blocco) in blocchi.enumerated() {
                await fase("Prendo appunti · parte \(indice + 1) di \(blocchi.count)…")
                note.append(try await appunti(blocco))
            }
            materiale = note.joined(separator: "\n\n")
            giro += 1
        }
        return materiale
    }

    /// Divide per righe, senza spezzare le frasi a metà.
    static func dividi(_ testo: String, massimo: Int) -> [String] {
        var blocchi: [String] = []
        var corrente = ""
        for riga in testo.split(separator: "\n", omittingEmptySubsequences: false) {
            if corrente.count + riga.count + 1 > massimo, !corrente.isEmpty {
                blocchi.append(corrente)
                corrente = ""
            }
            if riga.count > massimo {
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

// MARK: - Apple Intelligence (on-device)

/// Modello di Apple Intelligence sul dispositivo. Contesto piccolo (circa 4.000 token):
/// blocchi prudenti da 5.000 caratteri.
struct MotoreApple: MotoreVerbale {
    let nome = "Apple Intelligence"

    func genera(da trascrizione: String, fase: @escaping @MainActor (String) -> Void) async throws -> VerbaleGenerato {
        let materiale = try await Verbalista.riduci(trascrizione, massimo: 5_000, fase: fase) { blocco in
            let sessione = LanguageModelSession(instructions: Verbalista.istruzioniNote)
            return try await sessione.respond(to: "Parte di trascrizione:\n\n\(blocco)").content
        }
        await fase("Scrivo il verbale con Apple Intelligence…")
        let sessione = LanguageModelSession(instructions: Verbalista.istruzioniVerbale)
        return try await sessione.respond(
            to: "Redigi il verbale a partire da questo testo:\n\n\(materiale)",
            generating: VerbaleGenerato.self
        ).content
    }
}
