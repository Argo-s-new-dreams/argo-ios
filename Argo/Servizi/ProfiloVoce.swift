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

/// Calcola l'impronta della tua voce e la cerca tra i parlanti di un incontro.
/// Usa lo stesso modello della divisione delle voci (pipeline offline di FluidAudio):
/// `embedSpans` produce vettori dello stesso tipo di `DiarizationResult.speakerDatabase`.
enum RiconoscitoreVoce {

    /// Somiglianza coseno minima per dire «è la tua voce». Prudente: meglio non riconoscere che sbagliare.
    static let soglia: Float = 0.55
    private static let campioniAlSecondo = 16_000

    /// Impronta della voce da una registrazione dedicata (almeno 10 secondi di parlato).
    static func impronta(file url: URL) async throws -> [Float] {
        let campioni = try AudioConverter().resampleAudioFile(path: url.path)
        guard campioni.count >= campioniAlSecondo * 10 else { throw ErroreVoce.registrazioneCorta }
        let durata = Double(campioni.count) / Double(campioniAlSecondo)
        let gestore = try await Diarizzatore.gestorePronto()
        let impronte = try await gestore.embedSpans(
            audioSource: ArrayAudioSampleSource(samples: campioni),
            spans: [0..<durata]
        )
        guard let impronta = impronte.first, !impronta.isEmpty else { throw ErroreVoce.impronta }
        return impronta
    }

    /// Id (P1, P2…) del parlante che corrisponde al profilo, se la somiglianza supera la soglia.
    static func trova(_ profilo: ProfiloVoce, tra impronte: [String: [Float]]) -> String? {
        let migliore = impronte
            .map { (parlante: $0.key, somiglianza: coseno($0.value, profilo.impronta)) }
            .max { $0.somiglianza < $1.somiglianza }
        guard let migliore, migliore.somiglianza >= soglia else { return nil }
        return migliore.parlante
    }

    static func coseno(_ a: [Float], _ b: [Float]) -> Float {
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
    case registrazioneCorta, impronta
    var errorDescription: String? {
        switch self {
        case .registrazioneCorta: "Registrazione troppo corta: servono almeno 10 secondi di parlato."
        case .impronta: "Non sono riuscito a calcolare l'impronta della voce. Riprova in un posto più tranquillo."
        }
    }
}
