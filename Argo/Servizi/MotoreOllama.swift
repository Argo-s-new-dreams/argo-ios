import Foundation

/// Verbale scritto da Ollama sul Mac, in rete locale.
/// La trascrizione viaggia solo sulla tua Wi-Fi, dall'iPhone al tuo Mac.
struct MotoreOllama: MotoreVerbale {
    let indirizzo: URL
    let modello: String

    var nome: String { "Mac · \(modello)" }

    /// Contesto richiesto a Ollama e dimensione dei blocchi (circa 3 caratteri per token, con margine).
    private let contesto = 8_192
    private let caratteriPerBlocco = 12_000

    /// Legge indirizzo e modello dalle impostazioni; nil se non configurato.
    static func daImpostazioni() -> MotoreOllama? {
        let impostazioni = UserDefaults.standard
        guard let testo = impostazioni.string(forKey: "ollamaIndirizzo"),
              let url = normalizza(testo),
              let modello = impostazioni.string(forKey: "ollamaModello"), !modello.isEmpty
        else { return nil }
        return MotoreOllama(indirizzo: url, modello: modello)
    }

    /// Accetta "nome-mac.local", "192.168.1.20" o un URL completo; aggiunge http:// e la porta 11434.
    static func normalizza(_ testo: String) -> URL? {
        var t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "http://" + t }
        guard var componenti = URLComponents(string: t), componenti.host != nil else { return nil }
        if componenti.port == nil { componenti.port = 11434 }
        componenti.path = ""
        return componenti.url
    }

    // MARK: Verbale

    func genera(da trascrizione: String, fase: @escaping @MainActor (String) -> Void) async throws -> VerbaleGenerato {
        await fase(String(localized: "Contatto il Mac…"))
        let materiale = try await Verbalista.riduci(trascrizione, massimo: caratteriPerBlocco, fase: fase) { blocco in
            try await chat(
                sistema: Verbalista.istruzioniNote,
                utente: "Parte di trascrizione:\n\n\(blocco)",
                formato: nil
            )
        }
        await fase(String(localized: "Il Mac scrive il verbale con \(modello)…"))
        let json = try await chat(
            sistema: Verbalista.istruzioniVerbale + "\nRispondi solo con il JSON richiesto.",
            utente: "Redigi il verbale a partire da questo testo:\n\n\(materiale)",
            formato: Self.schemaVerbale
        )
        guard let dati = json.data(using: .utf8) else { throw ErroreOllama.rispostaNonValida }
        do {
            return try JSONDecoder().decode(VerbaleGenerato.self, from: dati)
        } catch {
            throw ErroreOllama.rispostaNonValida
        }
    }

    // MARK: API Ollama

    /// Modelli installati sul Mac (GET /api/tags). Serve anche come prova di connessione.
    static func modelli(su indirizzo: URL) async throws -> [String] {
        var richiesta = URLRequest(url: indirizzo.appending(path: "api/tags"))
        richiesta.timeoutInterval = 8
        let (dati, risposta) = try await eseguiRichiesta(richiesta)
        try controlla(risposta)
        struct Elenco: Decodable { struct Modello: Decodable { let name: String }; let models: [Modello] }
        return try JSONDecoder().decode(Elenco.self, from: dati).models.map(\.name).sorted()
    }

    private func chat(sistema: String, utente: String, formato: [String: Any]?) async throws -> String {
        var corpo: [String: Any] = [
            "model": modello,
            "stream": false,
            "messages": [
                ["role": "system", "content": sistema],
                ["role": "user", "content": utente]
            ],
            "options": ["num_ctx": contesto, "temperature": 0.2]
        ]
        if let formato { corpo["format"] = formato }

        var richiesta = URLRequest(url: indirizzo.appending(path: "api/chat"))
        richiesta.httpMethod = "POST"
        richiesta.setValue("application/json", forHTTPHeaderField: "Content-Type")
        richiesta.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        // Il primo caricamento del modello sul Mac può richiedere tempo.
        richiesta.timeoutInterval = 600

        let (dati, risposta) = try await Self.eseguiRichiesta(richiesta)
        try Self.controlla(risposta)
        struct Risposta: Decodable { struct Messaggio: Decodable { let content: String }; let message: Messaggio }
        return try JSONDecoder().decode(Risposta.self, from: dati).message.content
    }

    private static func eseguiRichiesta(_ richiesta: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: richiesta)
        } catch let errore as URLError {
            switch errore.code {
            case .cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                throw ErroreOllama.macNonRaggiungibile
            default:
                throw errore
            }
        }
    }

    private static func controlla(_ risposta: URLResponse) throws {
        guard let http = risposta as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 404: throw ErroreOllama.modelloNonTrovato
        default: throw ErroreOllama.http(http.statusCode)
        }
    }

    /// JSON Schema per l'output strutturato di Ollama.
    private static let schemaVerbale: [String: Any] = [
        "type": "object",
        "properties": [
            "titolo": ["type": "string"],
            "riassunto": ["type": "string"],
            "puntiChiave": ["type": "array", "items": ["type": "string"]],
            "azioni": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "descrizione": ["type": "string"],
                        "responsabile": ["type": "string"],
                        "scadenza": ["type": "string"]
                    ],
                    "required": ["descrizione"]
                ]
            ],
            "contatti": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "nome": ["type": "string"],
                        "azienda": ["type": "string"],
                        "ruolo": ["type": "string"],
                        "email": ["type": "string"],
                        "telefono": ["type": "string"],
                        "note": ["type": "string"]
                    ],
                    "required": ["nome"]
                ]
            ]
        ],
        "required": ["titolo", "riassunto", "puntiChiave", "azioni", "contatti"]
    ]
}

enum ErroreOllama: LocalizedError {
    case macNonRaggiungibile, modelloNonTrovato, rispostaNonValida, http(Int)

    var errorDescription: String? {
        switch self {
        case .macNonRaggiungibile:
            String(localized: "Non raggiungo il Mac. Controlla che sia acceso, sulla stessa Wi-Fi e che Ollama accetti connessioni dalla rete.")
        case .modelloNonTrovato:
            String(localized: "Il modello scelto non è installato sul Mac.")
        case .rispostaNonValida:
            String(localized: "Il Mac ha risposto, ma il verbale non è nel formato atteso. Prova un altro modello.")
        case .http(let codice):
            String(localized: "Il Mac ha risposto con un errore (HTTP \(codice)).")
        }
    }
}
