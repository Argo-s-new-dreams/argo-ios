import Foundation
import FluidAudio

/// Chi ha parlato e quando, sul dispositivo.
/// Usa FluidAudio (pipeline pyannote «community-1» convertita in CoreML).
/// I modelli si scaricano la prima volta, poi funziona offline.
enum Diarizzatore {

    struct Turno {
        let parlante: String
        let inizio: Double
        let fine: Double
    }

    static func turni(
        file url: URL,
        fase: @escaping @MainActor (String) -> Void
    ) async throws -> [Turno] {
        await fase("Riconosco i parlanti (la prima volta scarico il modello)…")
        let gestore = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await gestore.prepareModels()

        await fase("Divido le voci…")
        let campioni = try AudioConverter().resampleAudioFile(path: url.path)
        let risultato = try await gestore.process(audio: campioni)

        // Id della libreria → P1, P2… in ordine di prima apparizione.
        var mappa: [String: String] = [:]
        return risultato.segments
            .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
            .map { segmento in
                let originale = "\(segmento.speakerId)"
                let id: String
                if let esistente = mappa[originale] {
                    id = esistente
                } else {
                    id = "P\(mappa.count + 1)"
                    mappa[originale] = id
                }
                return Turno(
                    parlante: id,
                    inizio: Double(segmento.startTimeSeconds),
                    fine: Double(segmento.endTimeSeconds)
                )
            }
    }

    /// Assegna a ogni frase il parlante con la sovrapposizione maggiore
    /// (o il più vicino, se la frase cade in una pausa).
    static func assegna(_ turni: [Turno], a segmenti: [Segmento]) -> [Segmento] {
        guard !turni.isEmpty else { return segmenti }
        return segmenti.map { segmento in
            var copia = segmento
            var migliore: (parlante: String, valore: Double)?
            for turno in turni {
                let sovrapposizione = min(segmento.fine, turno.fine) - max(segmento.inizio, turno.inizio)
                if sovrapposizione > 0, sovrapposizione > (migliore?.valore ?? 0) {
                    migliore = (turno.parlante, sovrapposizione)
                }
            }
            if let migliore {
                copia.parlante = migliore.parlante
            } else {
                let centro = (segmento.inizio + segmento.fine) / 2
                copia.parlante = turni.min {
                    abs(($0.inizio + $0.fine) / 2 - centro) < abs(($1.inizio + $1.fine) / 2 - centro)
                }?.parlante
            }
            return copia
        }
    }
}
