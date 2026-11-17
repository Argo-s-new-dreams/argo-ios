import Foundation
import UniformTypeIdentifiers

/// Anagrafe voci importata da Argo desktop (file `.argovoci`, formato `argo.voci` v1).
/// Le impronte di pyannote community-1 (Mac) e FluidAudio (iPhone) sono nello stesso spazio:
/// verificato con `strumenti/prova-impronte` (somiglianza 0,94 sullo stesso audio).
/// Dati biometrici: restano solo qui, con protezione completa del file, e non vengono mai esportati.
struct AnagrafeVoci: Codable {
    struct Voce: Codable, Hashable {
        let nome: String
        let impronta: [Float]
        let campioni: Int?
    }

    let formato: String
    let versioneFormato: Int
    let motore: String?
    let creata: String?
    let soglia: Double?
    let voci: [Voce]
    /// Quando è arrivata su questo iPhone (assente nel file del desktop).
    var importata: Date?
}

extension UTType {
    static let anagrafeVoci = UTType(exportedAs: "blog.argosnewdreams.argovoci", conformingTo: .json)
}

enum ArchivioAnagrafe {
    private static var url: URL {
        let cartella = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella.appending(path: "anagrafe-voci.json")
    }

    static func carica() -> AnagrafeVoci? {
        guard let dati = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AnagrafeVoci.self, from: dati)
    }

    /// Importa un file `.argovoci` (da AirDrop, File o «Apri con»): sostituisce l'anagrafe precedente.
    @discardableResult
    static func importa(da origine: URL) throws -> AnagrafeVoci {
        let accesso = origine.startAccessingSecurityScopedResource()
        defer { if accesso { origine.stopAccessingSecurityScopedResource() } }
        let anagrafe = try importa(dati: Data(contentsOf: origine))
        // Il file ricevuto (es. Documents/Inbox di AirDrop) non deve restare in giro.
        if origine.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: origine) }
        return anagrafe
    }

    /// Importa un'anagrafe già in memoria (es. scaricata dal Ponte).
    @discardableResult
    static func importa(dati: Data) throws -> AnagrafeVoci {
        var anagrafe = try JSONDecoder().decode(AnagrafeVoci.self, from: dati)
        guard anagrafe.formato == "argo.voci", anagrafe.versioneFormato == 1 else {
            throw ErroreAnagrafe.formato
        }
        guard !anagrafe.voci.isEmpty, anagrafe.voci.allSatisfy({ $0.impronta.count == 256 }) else {
            throw ErroreAnagrafe.impronte
        }
        anagrafe.importata = .now
        try JSONEncoder().encode(anagrafe).write(to: url, options: [.atomic, .completeFileProtection])
        return anagrafe
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum ErroreAnagrafe: LocalizedError {
    case formato, impronte
    var errorDescription: String? {
        switch self {
        case .formato: "Il file non è un'anagrafe voci di Argo (formato argo.voci v1)."
        case .impronte: "L'anagrafe è vuota o contiene impronte non compatibili."
        }
    }
}
