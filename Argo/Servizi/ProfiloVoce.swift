import Foundation
import FluidAudio

/// Il profilo della voce di chi usa Argo: un'impronta (embedding) calcolata una volta.
/// È un dato biometrico: resta solo su questo iPhone, cifrato dal sistema,
/// e non finisce mai nel pacchetto Argo.
struct ProfiloVoce: Codable {
    var nome: String
    var impronta: [Float]
    var creato: Date
}

enum ArchivioVoce {
    private static var url: URL {
        let cartella = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella.appending(path: "profilo-voce.json")
    }

    static func carica() -> ProfiloVoce? {
        guard let dati = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProfiloVoce.self, from: dati)
    }

    static func salva(_ profilo: ProfiloVoce) throws {
        try JSONEncoder().encode(profilo).write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Calcola impronte vocali e trova la tua voce tra i parlanti di un incontro.
enum RiconoscitoreVoce {

    /// Somiglianza coseno minima per dire «è la tua voce». Prudente: meglio non riconoscere che sbagliare.
    static let soglia: Float = 0.55
    private static let campioniAlSecondo = 16_000

    /// Impronta della voce da una registrazione dedicata (almeno 10 secondi di parlato).
    static func impronta(file url: URL) async throws -> [Float] {
        let campioni = try AudioConverter().resampleAudioFile(path: url.path)
        guard campioni.count >= campioniAlSecondo * 10 else { throw ErroreVoce.registrazioneCorta }
        let estrattore = try await preparaEstrattore()
        return try await estrai(campioni, con: estrattore)
    }

    /// Restituisce l'id (P1, P2…) del parlante che corrisponde al profilo, se c'è.
    static func trova(
        _ profilo: ProfiloVoce,
        turni: [Diarizzatore.Turno],
        file url: URL
    ) async throws -> String? {
        let campioni = try AudioConverter().resampleAudioFile(path: url.path)
        let estrattore = try await preparaEstrattore()
        var migliore: (parlante: String, somiglianza: Float)?

        for parlante in Set(turni.map(\.parlante)) {
            // Fino a 30 secondi di parlato di questa voce, dai turni più lunghi di un secondo.
            var spezzone: [Float] = []
            for turno in turni where turno.parlante == parlante && turno.fine - turno.inizio >= 1 {
                let da = max(0, Int(turno.inizio * Double(campioniAlSecondo)))
                let a = min(campioni.count, Int(turno.fine * Double(campioniAlSecondo)))
                if a > da { spezzone.append(contentsOf: campioni[da..<a]) }
                if spezzone.count >= campioniAlSecondo * 30 { break }
            }
            guard spezzone.count >= campioniAlSecondo * 3 else { continue }

            let impronta = try await estrai(spezzone, con: estrattore)
            let somiglianza = coseno(impronta, profilo.impronta)
            if somiglianza > (migliore?.somiglianza ?? -1) {
                migliore = (parlante, somiglianza)
            }
        }

        guard let migliore, migliore.somiglianza >= soglia else { return nil }
        return migliore.parlante
    }

    // MARK: FluidAudio

    // `try await` anche dove la libreria potrebbe essere sincrona: al massimo un avviso,
    // mai un errore di compilazione se FluidAudio cambia firma tra una versione e l'altra.

    private static func preparaEstrattore() async throws -> DiarizerManager {
        let modelli = try await DiarizerModels.downloadIfNeeded()
        let diarizzatore = DiarizerManager()
        try await diarizzatore.initialize(models: modelli)
        return diarizzatore
    }

    private static func estrai(_ campioni: [Float], con diarizzatore: DiarizerManager) async throws -> [Float] {
        let impronta: [Float] = try await diarizzatore.extractEmbedding(campioni)
        return impronta
    }

    private static func coseno(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var prodotto: Float = 0, normaA: Float = 0, normaB: Float = 0
        for i in a.indices {
            prodotto += a[i] * b[i]
            normaA += a[i] * a[i]
            normaB += b[i] * b[i]
        }
        let denominatore = normaA.squareRoot() * normaB.squareRoot()
        return denominatore > 0 ? prodotto / denominatore : -1
    }
}

enum ErroreVoce: LocalizedError {
    case registrazioneCorta
    var errorDescription: String? { "Registrazione troppo corta: servono almeno 10 secondi di parlato." }
}
