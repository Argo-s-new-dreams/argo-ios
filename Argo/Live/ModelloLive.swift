import CryptoKit
import Foundation

/// Il modello di Argo Live sul telefono: Gemma 4 E2B in formato LiteRT-LM (Apache 2.0), scaricato una volta da
/// Hugging Face con revisione e SHA-256 fissi. Resta in Application Support, escluso dal backup di iCloud.
/// Prototipo di laboratorio: i testi non sono tradotti (sono `verbatim`).
enum ModelloLive {
    static let nomeFile = "gemma-4-E2B-it.litertlm"
    static let revisione = "2e12bfd869b2962984f97a1f2a26807316d534cc"
    static let byte: Int64 = 2_588_147_712
    static let sha256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
    static let indirizzo = URL(string:
        "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/\(revisione)/\(nomeFile)")!

    static var cartella: URL {
        URL.applicationSupportDirectory.appending(path: "Live", directoryHint: .isDirectory)
    }
    static var file: URL { cartella.appending(path: nomeFile) }
    static var cache: URL {
        URL.cachesDirectory.appending(path: "LiveCache", directoryHint: .isDirectory)
    }

    static var presente: Bool {
        let attributi = try? FileManager.default.attributesOfItem(atPath: file.path)
        return (attributi?[.size] as? Int64) == byte
    }

    static var megabyte: Int { Int(byte / 1_000_000) }

    /// Spazio libero sufficiente: il file più un margine di 1 GB.
    static var spazioSufficiente: Bool {
        let valori = try? URL.applicationSupportDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let libero = valori?.volumeAvailableCapacityForImportantUsage else { return true }
        return libero > byte + 1_000_000_000
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: cache)
    }

    /// Controllo SHA-256 a blocchi da 8 MB (qualche secondo su 2,6 GB).
    static func verifica(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let blocco = try handle.read(upToCount: 8 * 1_048_576), !blocco.isEmpty {
            hash.update(data: blocco)
        }
        let esadecimale = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return esadecimale == sha256
    }

    /// Sposta il file scaricato al suo posto e lo esclude dal backup.
    static func installa(da temporaneo: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cartella, withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        try fm.moveItem(at: temporaneo, to: file)
        var destinazione = file
        var valori = URLResourceValues()
        valori.isExcludedFromBackup = true
        try destinazione.setResourceValues(valori)
    }
}

/// Download con avanzamento. Il file temporaneo di URLSession sparisce al ritorno del delegate: lo spostiamo subito.
final class ScaricatoreLive: NSObject, URLSessionDownloadDelegate {
    private let avanzamento: @MainActor (Double) -> Void
    private let fine: @MainActor (Result<URL, Error>) -> Void
    private var sessione: URLSession?
    private var compito: URLSessionDownloadTask?

    init(avanzamento: @escaping @MainActor (Double) -> Void,
         fine: @escaping @MainActor (Result<URL, Error>) -> Void) {
        self.avanzamento = avanzamento
        self.fine = fine
    }

    func avvia() {
        let configurazione = URLSessionConfiguration.default
        configurazione.timeoutIntervalForResource = 3 * 60 * 60
        let sessione = URLSession(configuration: configurazione, delegate: self, delegateQueue: nil)
        self.sessione = sessione
        compito = sessione.downloadTask(with: ModelloLive.indirizzo)
        compito?.resume()
    }

    func annulla() {
        compito?.cancel()
        sessione?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let totale = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : ModelloLive.byte
        let frazione = Double(totalBytesWritten) / Double(totale)
        Task { @MainActor in avanzamento(frazione) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let appoggio = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".litertlm")
        do {
            try FileManager.default.moveItem(at: location, to: appoggio)
            Task { @MainActor in fine(.success(appoggio)) }
        } catch {
            Task { @MainActor in fine(.failure(error)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @MainActor in fine(.failure(error)) }
        }
        session.finishTasksAndInvalidate()
    }
}
