import Foundation
import SwiftData

/// Una registrazione con la sua trascrizione e il verbale generato.
@Model
final class Sessione {
    var id: UUID
    var creata: Date
    var titolo: String
    var lingua: String
    var durata: TimeInterval
    var nomeFileAudio: String?
    var trascrizione: String
    var riassunto: String
    var puntiChiave: [String]
    var azioni: [Azione]
    var stato: StatoSessione
    var messaggioErrore: String?

    init(titolo: String, lingua: String, durata: TimeInterval, nomeFileAudio: String?) {
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
    }

    var urlAudio: URL? {
        nomeFileAudio.map { Archivio.cartellaAudio.appending(path: $0) }
    }

    /// Elimina il file audio dal dispositivo, se presente.
    func eliminaAudio() {
        if let url = urlAudio {
            try? FileManager.default.removeItem(at: url)
        }
        nomeFileAudio = nil
    }

    /// Verbale in Markdown, pronto da condividere (Mail, Note, Teams…).
    var markdown: String {
        var testo = "# \(titolo)\n\n"
        testo += "_\(creata.formatted(date: .long, time: .shortened)) · \(Formato.durata(durata))_\n\n"
        if !riassunto.isEmpty {
            testo += "## Riassunto\n\n\(riassunto)\n\n"
        }
        if !puntiChiave.isEmpty {
            testo += "## Punti chiave\n\n" + puntiChiave.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !azioni.isEmpty {
            testo += "## Azioni\n\n" + azioni.map { "- [ ] \($0.testoCompleto)" }.joined(separator: "\n") + "\n\n"
        }
        if !trascrizione.isEmpty {
            testo += "## Trascrizione\n\n\(trascrizione)\n"
        }
        testo += "\n---\nGenerato con Argo per iPhone · elaborazione 100% sul dispositivo\n"
        return testo
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

enum StatoSessione: String, Codable {
    case registrata, inTrascrizione, trascritta, completata, errore
}

enum Archivio {
    /// Cartella Documenti/Audio dell'app: non sincronizzata altrove.
    static var cartellaAudio: URL {
        let url = URL.documentsDirectory.appending(path: "Audio", directoryHint: .isDirectory)
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
