import AVFoundation

/// Apre l'audio di un incontro per trascrizione e voci.
///
/// Di norma il file si apre così com'è. Se iOS non lo apre (per esempio un vecchio `.m4a` chiuso male
/// da una registrazione interrotta: errore «wht?» 2003334207), si prova a decodificarlo con
/// `AVAssetReader` in una copia PCM temporanea, che va poi eliminata con `elimina(_:originale:)`.
enum LettoreAudio {

    /// URL che `AVAudioFile` e FluidAudio sanno leggere: l'originale oppure una copia riparata.
    static func leggibile(_ url: URL) async throws -> URL {
        if (try? AVAudioFile(forReading: url)) != nil { return url }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try await LettoreAudio.decodifica(url)
            }.value
        } catch {
            throw ErroreAudio.danneggiato
        }
    }

    /// Elimina la copia riparata (se c'è): l'audio non deve restare sul telefono più del necessario.
    static func elimina(_ url: URL, originale: URL) {
        if url != originale { try? FileManager.default.removeItem(at: url) }
    }

    private static func decodifica(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let traccia = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ErroreAudio.danneggiato
        }
        let lettore = try AVAssetReader(asset: asset)
        let uscita = AVAssetReaderTrackOutput(track: traccia, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        lettore.add(uscita)
        guard lettore.startReading() else { throw lettore.error ?? ErroreAudio.danneggiato }

        guard let formato = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                          channels: 1, interleaved: true) else {
            throw ErroreAudio.danneggiato
        }
        let destinazione = Archivio.cartellaAudio.appending(path: "argo-riparato-\(UUID().uuidString).caf")
        var scritti: AVAudioFrameCount = 0
        do {
            let file = try AVAudioFile(forWriting: destinazione, settings: formato.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
            while let campione = uscita.copyNextSampleBuffer() {
                guard let blocco = CMSampleBufferGetDataBuffer(campione) else { continue }
                let byte = CMBlockBufferGetDataLength(blocco)
                let frame = AVAudioFrameCount(byte / 2)
                guard frame > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: frame),
                      let canale = buffer.int16ChannelData?[0] else { continue }
                buffer.frameLength = frame
                guard CMBlockBufferCopyDataBytes(blocco, atOffset: 0, dataLength: Int(frame) * 2,
                                                 destination: canale) == kCMBlockBufferNoErr else { continue }
                try file.write(from: buffer)
                scritti += frame
            }
        } catch {
            try? FileManager.default.removeItem(at: destinazione)
            throw error
        }
        guard lettore.status == .completed, scritti > 0 else {
            try? FileManager.default.removeItem(at: destinazione)
            throw lettore.error ?? ErroreAudio.danneggiato
        }
        return destinazione
    }
}

enum ErroreAudio: LocalizedError {
    case danneggiato
    var errorDescription: String? {
        String(localized: "Il file audio di questo incontro è danneggiato: probabilmente la registrazione si è interrotta in modo anomalo (telefonata, app chiusa dal sistema). Argo ha provato a recuperarlo senza riuscirci: puoi eliminare l'incontro.")
    }
}
