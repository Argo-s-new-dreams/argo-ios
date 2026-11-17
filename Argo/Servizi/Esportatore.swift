import Foundation

/// Crea il «pacchetto Argo»: uno .zip con sessione.json, trascrizione, relazione e foto.
/// Formato descritto in docs/FORMATO-PACCHETTO.md, pensato per Argo desktop (Mac/Windows) e futuri client.
@MainActor
enum Esportatore {

    static let versioneFormato = 1

    static func pacchetto(di sessione: Sessione) throws -> URL {
        let gestore = FileManager.default
        let nome = nomeFile(sessione)
        let base = gestore.temporaryDirectory.appending(path: "argo-export", directoryHint: .isDirectory)
        let cartella = base.appending(path: nome, directoryHint: .isDirectory)
        try? gestore.removeItem(at: cartella)
        try gestore.createDirectory(at: cartella.appending(path: "foto"), withIntermediateDirectories: true)

        // Foto, rinominate in ordine di scatto: foto/01.jpg, foto/02.jpg…
        var fotoEsportate: [PacchettoArgo.Foto] = []
        for (indice, foto) in sessione.foto.sorted(by: { $0.secondo < $1.secondo }).enumerated() {
            let file = String(format: "foto/%02d.jpg", indice + 1)
            if gestore.fileExists(atPath: foto.url.path) {
                try gestore.copyItem(at: foto.url, to: cartella.appending(path: file))
            }
            fotoEsportate.append(.init(file: file, secondo: foto.secondo, testo: foto.testoOCR, riferimenti: foto.riferimenti))
        }

        let pacchetto = PacchettoArgo(
            formato: "argo.sessione",
            versioneFormato: versioneFormato,
            app: "Argo per iPhone \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")",
            id: sessione.id,
            creata: sessione.creata,
            titolo: sessione.titolo,
            lingua: sessione.lingua,
            durata: sessione.durata,
            partecipanti: sessione.parlanti.map { .init(id: $0, nome: sessione.nome(di: $0) ?? $0) },
            segmenti: sessione.segmenti.map { .init(inizio: $0.inizio, fine: $0.fine, parlante: $0.parlante, testo: $0.testo) },
            foto: fotoEsportate,
            relazione: sessione.stato == .completata ? .init(
                motore: sessione.motoreVerbale,
                riassunto: sessione.riassunto,
                puntiChiave: sessione.puntiChiave,
                azioni: sessione.azioni.map { .init(descrizione: $0.descrizione, responsabile: $0.responsabile, scadenza: $0.scadenza) },
                contatti: sessione.contatti.map {
                    .init(nome: $0.nome, azienda: $0.azienda, ruolo: $0.ruolo, email: $0.email, telefono: $0.telefono, note: $0.note)
                }
            ) : nil,
            trascrizioneLegacy: sessione.segmenti.isEmpty ? sessione.trascrizione : nil
        )

        let codificatore = JSONEncoder()
        codificatore.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        codificatore.dateEncodingStrategy = .iso8601
        try codificatore.encode(pacchetto).write(to: cartella.appending(path: "sessione.json"))
        try Data(sessione.markdown.utf8).write(to: cartella.appending(path: "relazione.md"))

        return try comprimi(cartella, in: base.appending(path: "\(nome).zip"))
    }

    /// Zip con il meccanismo di sistema (NSFileCoordinator .forUploading), senza librerie esterne.
    private static func comprimi(_ cartella: URL, in destinazione: URL) throws -> URL {
        var erroreCoordinamento: NSError?
        var erroreCopia: Error?
        NSFileCoordinator().coordinate(readingItemAt: cartella, options: [.forUploading], error: &erroreCoordinamento) { zip in
            do {
                try? FileManager.default.removeItem(at: destinazione)
                try FileManager.default.copyItem(at: zip, to: destinazione)
            } catch {
                erroreCopia = error
            }
        }
        if let erroreCoordinamento { throw erroreCoordinamento }
        if let erroreCopia { throw erroreCopia }
        return destinazione
    }

    private static func nomeFile(_ sessione: Sessione) -> String {
        let formatoData = DateFormatter()
        formatoData.locale = Locale(identifier: "en_US_POSIX")
        formatoData.dateFormat = "yyyy-MM-dd-HHmm"
        let data = formatoData.string(from: sessione.creata)
        let titolo = sessione.titolo
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        return "Argo-\(data)" + (titolo.isEmpty ? "" : "-\(titolo)")
    }
}

/// Contenuto di sessione.json (versioneFormato 1).
struct PacchettoArgo: Codable {
    struct Partecipante: Codable { let id: String; let nome: String }
    struct Segmento: Codable { let inizio: Double; let fine: Double; let parlante: String?; let testo: String }
    struct Foto: Codable { let file: String; let secondo: Double; let testo: String; let riferimenti: [String] }
    struct Azione: Codable { let descrizione: String; let responsabile: String?; let scadenza: String? }
    struct Contatto: Codable {
        let nome: String; let azienda: String?; let ruolo: String?
        let email: String?; let telefono: String?; let note: String?
    }
    struct Relazione: Codable {
        let motore: String?; let riassunto: String; let puntiChiave: [String]
        let azioni: [Azione]; let contatti: [Contatto]
    }

    let formato: String
    let versioneFormato: Int
    let app: String
    let id: UUID
    let creata: Date
    let titolo: String
    let lingua: String
    let durata: Double
    let partecipanti: [Partecipante]
    let segmenti: [Segmento]
    let foto: [Foto]
    let relazione: Relazione?
    let trascrizioneLegacy: String?
}
