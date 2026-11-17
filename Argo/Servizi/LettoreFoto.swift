import UIKit
import Vision

/// Salvataggio e lettura (OCR) delle foto, tutto sul dispositivo.
enum LettoreFoto {

    /// Salva la foto raddrizzata e ridimensionata (lato lungo 2.048 px) in Documenti/Foto.
    static func salva(_ immagine: UIImage) throws -> String {
        let lato: CGFloat = 2_048
        let scala = min(1, lato / max(immagine.size.width, immagine.size.height))
        let dimensione = CGSize(width: immagine.size.width * scala, height: immagine.size.height * scala)
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        // Ridisegnare porta l'orientamento a .up: l'OCR non deve preoccuparsene.
        let raddrizzata = UIGraphicsImageRenderer(size: dimensione, format: formato).image { _ in
            immagine.draw(in: CGRect(origin: .zero, size: dimensione))
        }
        guard let dati = raddrizzata.jpegData(compressionQuality: 0.85) else {
            throw ErroreFoto.salvataggio
        }
        let nome = "foto-\(UUID().uuidString).jpg"
        try dati.write(to: Archivio.cartellaFoto.appending(path: nome), options: .completeFileProtectionUntilFirstUserAuthentication)
        return nome
    }

    /// Legge il testo (biglietti da visita, documenti, cartellini) e ne estrae i riferimenti.
    static func leggi(_ url: URL) async -> (testo: String, riferimenti: [String]) {
        await Task.detached(priority: .userInitiated) {
            guard let immagine = UIImage(contentsOfFile: url.path), let cg = immagine.cgImage else {
                return ("", [])
            }
            let richiesta = VNRecognizeTextRequest()
            richiesta.recognitionLevel = .accurate
            richiesta.usesLanguageCorrection = true
            richiesta.recognitionLanguages = ["it-IT", "en-US", "de-DE", "fr-FR", "es-ES"]
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([richiesta])
            } catch {
                return ("", [])
            }
            let righe = (richiesta.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let testo = righe.joined(separator: "\n")
            return (testo, riferimenti(in: testo))
        }.value
    }

    /// Telefoni, email, siti e indirizzi trovati nel testo.
    private static func riferimenti(in testo: String) -> [String] {
        let tipi: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let rilevatore = try? NSDataDetector(types: tipi.rawValue) else { return [] }
        let intervallo = NSRange(testo.startIndex..., in: testo)
        var trovati: [String] = []
        for risultato in rilevatore.matches(in: testo, range: intervallo) {
            let valore: String?
            switch risultato.resultType {
            case .phoneNumber: valore = risultato.phoneNumber
            case .link: valore = risultato.url?.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            default: valore = Range(risultato.range, in: testo).map { String(testo[$0]) }
            }
            if let valore, !trovati.contains(valore) { trovati.append(valore) }
        }
        return trovati
    }
}

enum ErroreFoto: LocalizedError {
    case salvataggio
    var errorDescription: String? { "Non riesco a salvare la foto." }
}
