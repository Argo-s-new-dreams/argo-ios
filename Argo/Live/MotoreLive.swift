import Foundation
import LiteRTLM

/// Gemma 4 E2B con LiteRT-LM: carica il modello, tiene una conversazione e risponde a pezzi (streaming),
/// così la voce può partire alle prime parole. Pensiero (thinking) spento: per la voce serve la risposta subito.
final class MotoreLive {
    private var motore: Engine?
    private var conversazione: Conversation?
    private(set) var gpu = true

    var caricato: Bool { motore != nil }

    /// Carica il modello (qualche secondo la prima volta: LiteRT compila e mette in cache). Ritorna i secondi.
    func carica(gpu: Bool) async throws -> Double {
        let inizio = Date()
        try FileManager.default.createDirectory(at: ModelloLive.cache, withIntermediateDirectories: true)
#if targetEnvironment(simulator)
        // Il Metal del simulatore non ha i «residency set»: LiteRT-LM si fermerebbe con un assert.
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.gpuEnableMetalResidencySet = false
#endif
        let configurazione = try EngineConfig(
            modelPath: ModelloLive.file.path,
            backend: gpu ? .gpu : .cpu(threadCount: 4),
            maxNumTokens: 2048,
            cacheDir: ModelloLive.cache.path
        )
        let nuovo = Engine(engineConfig: configurazione)
        try await nuovo.initialize()
        motore = nuovo
        self.gpu = gpu
        conversazione = nil
        return Date().timeIntervalSince(inizio)
    }

    func scarica() {
        try? conversazione?.cancel()
        conversazione = nil
        motore = nil
    }

    /// Nuova conversazione nella lingua scelta (dimentica le domande precedenti).
    func nuovaConversazione(lingua: String) async throws {
        guard let motore else { throw ErroreLive.modelloNonCaricato }
        let configurazione = ConversationConfig(
            systemMessage: Message(Self.istruzioni(lingua), role: .system),
            thinkingConfig: ThinkingConfig(enableThinking: false)
        )
        conversazione = try await motore.createConversation(with: configurazione)
    }

    /// Risposta a pezzi di testo.
    func rispondi(_ domanda: String, lingua: String) async throws -> AsyncThrowingStream<String, Error> {
        if conversazione == nil { try await nuovaConversazione(lingua: lingua) }
        guard let conversazione else { throw ErroreLive.modelloNonCaricato }
        let sorgente = conversazione.sendMessageStream(Message(domanda), maxOutputTokens: 300)
        return AsyncThrowingStream { continuazione in
            let compito = Task {
                do {
                    for try await pezzo in sorgente {
                        continuazione.yield(pezzo.toString)
                    }
                    continuazione.finish()
                } catch {
                    continuazione.finish(throwing: error)
                }
            }
            continuazione.onTermination = { _ in compito.cancel() }
        }
    }

    func interrompi() {
        try? conversazione?.cancel()
    }

    /// Misure dell'ultima risposta secondo LiteRT-LM.
    func misure() -> BenchmarkInfo? {
        try? conversazione?.getBenchmarkInfo()
    }

    static func istruzioni(_ lingua: String) -> String {
        switch lingua.prefix(2) {
        case "en":
            "You are Argo, a voice assistant. Answer in English, briefly and conversationally: at most three sentences, no lists, no markdown and no emoji, because your answer is read aloud."
        case "es":
            "Eres Argo, un asistente de voz. Responde en español, de forma breve y coloquial: como máximo tres frases, sin listas, sin markdown y sin emojis, porque la respuesta se lee en voz alta."
        case "de":
            "Du bist Argo, ein Sprachassistent. Antworte auf Deutsch, kurz und im Gesprächston: höchstens drei Sätze, keine Listen, kein Markdown und keine Emojis, denn die Antwort wird vorgelesen."
        default:
            "Sei Argo, un assistente vocale. Rispondi in italiano, in modo breve e colloquiale: al massimo tre frasi, senza elenchi, senza markdown e senza emoji, perché la risposta viene letta ad alta voce."
        }
    }
}

enum ErroreLive: LocalizedError {
    case modelloNonCaricato
    case linguaNonSupportata(String)
    case nonAutorizzato
    case formatoAudio
    case hashErrato

    var errorDescription: String? {
        switch self {
        case .modelloNonCaricato: "Il modello non è caricato."
        case .linguaNonSupportata(let codice): "La lingua \(codice) non è supportata dalla trascrizione sul dispositivo."
        case .nonAutorizzato: "Servono i permessi di microfono e riconoscimento vocale (Impostazioni › Argo)."
        case .formatoAudio: "Formato audio non disponibile per la trascrizione."
        case .hashErrato: "Il file scaricato non corrisponde (SHA-256 diverso): l'ho eliminato. Riprova."
        }
    }
}
