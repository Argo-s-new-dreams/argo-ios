import AVFoundation
import Speech

/// Trascrizione sul dispositivo con SpeechAnalyzer / SpeechTranscriber (iOS 26).
/// I modelli linguistici vengono scaricati da Apple la prima volta e poi restano sul telefono.
enum Trascrittore {

    /// Lingue della riunione (indipendenti dalla lingua dell'app), con il nome nella lingua dell'app.
    static var lingueProposte: [(codice: String, nome: String)] {
        ["it-IT", "en-US", "en-GB", "de-DE", "fr-FR", "es-ES"].map { codice in
            (codice, Locale.current.localizedString(forIdentifier: codice)?.localizedCapitalized ?? codice)
        }
    }

    static func trascrivi(
        file url: URL,
        lingua codice: String,
        fase: @escaping @MainActor (String) -> Void
    ) async throws -> [Segmento] {
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
            await fase(String(localized: "Scarico il modello per la lingua (solo la prima volta)…"))
            try await richiesta.downloadAndInstall()
        }

        await fase(String(localized: "Trascrivo sul dispositivo…"))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        let raccolta = Task { () throws -> [Segmento] in
            var segmenti: [Segmento] = []
            for try await risultato in transcriber.results {
                let testo = String(risultato.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !testo.isEmpty else { continue }
                let inizio = risultato.range.start.seconds
                let fine = risultato.range.end.seconds
                let ultimaFine = segmenti.last?.fine ?? 0
                segmenti.append(Segmento(
                    inizio: inizio.isFinite ? inizio : ultimaFine,
                    fine: fine.isFinite ? fine : ultimaFine,
                    testo: testo
                ))
            }
            return segmenti
        }

        if let ultimoCampione = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: ultimoCampione)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let segmenti = try await raccolta.value
        guard !segmenti.isEmpty else { throw ErroreTrascrizione.nessunParlato }
        return segmenti
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
            String(localized: "Serve il permesso di riconoscimento vocale: lo trovi in Impostazioni › Privacy › Riconoscimento vocale.")
        case .linguaNonSupportata(let codice):
            String(localized: "La lingua \(codice) non è supportata dalla trascrizione sul dispositivo.")
        case .nessunParlato:
            String(localized: "Non ho trovato parlato nella registrazione.")
        }
    }
}
