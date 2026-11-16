import AVFoundation
import Speech

/// Trascrizione sul dispositivo con SpeechAnalyzer / SpeechTranscriber (iOS 26).
/// I modelli linguistici vengono scaricati da Apple la prima volta e poi restano sul telefono.
enum Trascrittore {

    static let lingueProposte: [(codice: String, nome: String)] = [
        ("it-IT", "Italiano"),
        ("en-US", "Inglese (USA)"),
        ("en-GB", "Inglese (UK)"),
        ("de-DE", "Tedesco"),
        ("fr-FR", "Francese"),
        ("es-ES", "Spagnolo")
    ]

    static func trascrivi(
        file url: URL,
        lingua codice: String,
        fase: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard await autorizzazione() else { throw ErroreTrascrizione.nonAutorizzato }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: codice)) else {
            throw ErroreTrascrizione.linguaNonSupportata(codice)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        if let richiesta = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await fase("Scarico il modello per la lingua (solo la prima volta)…")
            try await richiesta.downloadAndInstall()
        }

        await fase("Trascrivo sul dispositivo…")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        let raccolta = Task { () throws -> [String] in
            var righe: [String] = []
            for try await risultato in transcriber.results {
                let testo = String(risultato.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !testo.isEmpty else { continue }
                let inizio = risultato.range.start.seconds
                let marca = inizio.isFinite ? "[\(Formato.durata(inizio))] " : ""
                righe.append(marca + testo)
            }
            return righe
        }

        if let ultimoCampione = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: ultimoCampione)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let righe = try await raccolta.value
        guard !righe.isEmpty else { throw ErroreTrascrizione.nessunParlato }
        return righe.joined(separator: "\n")
    }

    /// Permesso di riconoscimento vocale (chiesto una sola volta dal sistema).
    private static func autorizzazione() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuazione in
            SFSpeechRecognizer.requestAuthorization { stato in
                continuazione.resume(returning: stato == .authorized)
            }
        }
    }
}

enum ErroreTrascrizione: LocalizedError {
    case linguaNonSupportata(String)
    case nessunParlato
    case nonAutorizzato

    var errorDescription: String? {
        switch self {
        case .nonAutorizzato:
            "Serve il permesso di riconoscimento vocale: lo trovi in Impostazioni › Privacy › Riconoscimento vocale."
        case .linguaNonSupportata(let codice):
            "La lingua \(codice) non è supportata dalla trascrizione sul dispositivo."
        case .nessunParlato:
            "Non ho trovato parlato nella registrazione."
        }
    }
}
