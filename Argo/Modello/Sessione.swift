import Foundation
import SwiftData

/// Un incontro: registrazione, foto scattate durante, trascrizione con i parlanti e relazione.
@Model
final class Sessione {
    var id: UUID
    var creata: Date
    var titolo: String
    var lingua: String
    var durata: TimeInterval
    var nomeFileAudio: String?
    /// Testo semplice (compatibilità 0.1–0.2 e controlli rapidi).
    var trascrizione: String
    var riassunto: String
    var puntiChiave: [String]
    var azioni: [Azione]
    var stato: StatoSessione
    var messaggioErrore: String?
    /// Informazione non bloccante (es. nessun motore per la relazione).
    var avviso: String?
    /// Chi ha scritto la relazione (Apple Intelligence o Mac · modello).
    var motoreVerbale: String?

    // 0.3 · taccuino da fiera
    var segmenti: [Segmento] = []
    var foto: [FotoSessione] = []
    /// Id parlante (P1, P2…) → nome scelto dall'utente.
    var nomiParlanti: [String: String] = [:]
    var contatti: [Contatto] = []
    /// 0.6 · quando è stata consegnata ad Argo sul computer tramite il Ponte.
    var inviataAdArgo: Date? = nil

    init(titolo: String, lingua: String, durata: TimeInterval, nomeFileAudio: String?, foto: [FotoSessione] = []) {
        self.id = UUID()
        self.creata = .now
        self.titolo = titolo
        self.lingua = lingua
        self.durata = durata
        self.nomeFileAudio = nomeFileAudio
        self.trascrizione = ""
        self.riassunto = ""
        self.puntiChiave = []
        self.azioni = []
        self.stato = .registrata
        self.foto = foto
    }

    var urlAudio: URL? {
        nomeFileAudio.map { Archivio.cartellaAudio.appending(path: $0) }
    }

    var haTrascrizione: Bool { !segmenti.isEmpty || !trascrizione.isEmpty }

    /// Parlanti in ordine di prima apparizione.
    var parlanti: [String] {
        var visti: [String] = []
        for s in segmenti { if let p = s.parlante, !visti.contains(p) { visti.append(p) } }
        return visti
    }

    func nome(di parlante: String?) -> String? {
        guard let parlante else { return nil }
        let nome = nomiParlanti[parlante]?.trimmingCharacters(in: .whitespaces) ?? ""
        return nome.isEmpty ? "Parlante \(parlante.dropFirst())" : nome
    }

    /// Cronologia: parole e foto in ordine di tempo.
    var cronologia: [VoceCronologia] {
        let parole = segmenti.map { VoceCronologia.parole($0) }
        let scatti = foto.map { VoceCronologia.foto($0) }
        return (parole + scatti).sorted { $0.secondo < $1.secondo }
    }

    /// Testo per il modello e per l'esportazione: parlanti con i loro nomi, foto con il testo letto.
    var testoCompleto: String {
        guard !segmenti.isEmpty else { return trascrizione }
        var numeroFoto = 0
        return cronologia.map { voce in
            switch voce {
            case .parole(let s):
                let chi = nome(di: s.parlante).map { "\($0): " } ?? ""
                return "[\(Formato.durata(s.inizio))] \(chi)\(s.testo)"
            case .foto(let f):
                numeroFoto += 1
                let letto = f.testoOCR.isEmpty ? "nessun testo leggibile" : f.testoOCR.replacingOccurrences(of: "\n", with: " · ")
                return "[\(Formato.durata(f.secondo))] 📷 FOTO \(numeroFoto): \(letto)"
            }
        }.joined(separator: "\n")
    }

    /// Elimina il file audio dal dispositivo, se presente.
    func eliminaAudio() {
        if let url = urlAudio { try? FileManager.default.removeItem(at: url) }
        nomeFileAudio = nil
    }

    /// Elimina audio e foto: da chiamare prima di cancellare la sessione.
    func eliminaFile() {
        eliminaAudio()
        for f in foto { try? FileManager.default.removeItem(at: f.url) }
    }

    /// Relazione in Markdown, pronta da condividere.
    var markdown: String {
        var testo = "# \(titolo)\n\n"
        testo += "_\(creata.formatted(date: .long, time: .shortened)) · \(Formato.durata(durata))_\n\n"
        if !riassunto.isEmpty { testo += "## Riassunto\n\n\(riassunto)\n\n" }
        if !contatti.isEmpty {
            testo += "## Contatti\n\n" + contatti.map { "- \($0.descrizione)" }.joined(separator: "\n") + "\n\n"
        }
        if !puntiChiave.isEmpty {
            testo += "## Punti chiave\n\n" + puntiChiave.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !azioni.isEmpty {
            testo += "## Azioni\n\n" + azioni.map { "- [ ] \($0.testoCompleto)" }.joined(separator: "\n") + "\n\n"
        }
        if haTrascrizione { testo += "## Trascrizione\n\n\(testoCompleto)\n" }
        let origine = motoreVerbale.map { "relazione: \($0)" } ?? "solo trascrizione"
        testo += "\n---\nGenerato con Argo per iPhone · trascrizione sul dispositivo · \(origine)\n"
        return testo
    }
}

struct Segmento: Codable, Hashable, Identifiable {
    var id = UUID()
    var inizio: Double
    var fine: Double
    var parlante: String?
    var testo: String
}

struct FotoSessione: Codable, Hashable, Identifiable {
    var id = UUID()
    var nomeFile: String
    /// Secondo della registrazione in cui è stata scattata.
    var secondo: Double
    var testoOCR: String = ""
    /// Telefoni, email, link e indirizzi riconosciuti nel testo.
    var riferimenti: [String] = []
    var letta = false

    var url: URL { Archivio.cartellaFoto.appending(path: nomeFile) }
}

enum VoceCronologia: Identifiable {
    case parole(Segmento)
    case foto(FotoSessione)

    var id: UUID {
        switch self {
        case .parole(let s): s.id
        case .foto(let f): f.id
        }
    }

    var secondo: Double {
        switch self {
        case .parole(let s): s.inizio
        case .foto(let f): f.secondo
        }
    }
}

struct Azione: Codable, Hashable, Identifiable {
    var id = UUID()
    var descrizione: String
    var responsabile: String?
    var scadenza: String?

    var testoCompleto: String {
        var parti = [descrizione]
        if let responsabile, !responsabile.isEmpty { parti.append("(\(responsabile))") }
        if let scadenza, !scadenza.isEmpty { parti.append("entro \(scadenza)") }
        return parti.joined(separator: " ")
    }
}

struct Contatto: Codable, Hashable, Identifiable {
    var id = UUID()
    var nome: String
    var azienda: String?
    var ruolo: String?
    var email: String?
    var telefono: String?
    var note: String?

    var descrizione: String {
        let dettagli = [ruolo, azienda, email, telefono, note]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return dettagli.isEmpty ? nome : "\(nome) · " + dettagli.joined(separator: " · ")
    }
}

enum StatoSessione: String, Codable {
    case registrata, inTrascrizione, trascritta, completata, errore
}

enum Archivio {
    static var cartellaAudio: URL { cartella("Audio") }
    static var cartellaFoto: URL { cartella("Foto") }

    private static func cartella(_ nome: String) -> URL {
        let url = URL.documentsDirectory.appending(path: nome, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum Formato {
    static func durata(_ secondi: TimeInterval) -> String {
        let totale = Int(secondi.rounded())
        let (h, m, s) = (totale / 3600, (totale % 3600) / 60, totale % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
