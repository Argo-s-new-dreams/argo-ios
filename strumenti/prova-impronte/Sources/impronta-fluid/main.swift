// impronta-fluid file1.wav [file2.wav …] > fluid.json
// Per ogni file (una sola persona che parla) stampa l'impronta calcolata come fa Argo per iPhone:
// pipeline offline di FluidAudio, `embedSpans` sull'intero audio (stesso tipo di vettori
// di `DiarizationResult.speakerDatabase`, usati per riconoscere le voci negli incontri).
import Foundation
import FluidAudio

let file = Array(CommandLine.arguments.dropFirst())
guard !file.isEmpty else {
    FileHandle.standardError.write(Data("uso: impronta-fluid file.wav [altri…]\n".utf8))
    exit(1)
}

let gestore = OfflineDiarizerManager(config: .default)
try await gestore.prepareModels()

var risultati: [String: [Float]] = [:]
for percorso in file {
    let campioni = try AudioConverter().resampleAudioFile(path: percorso)
    let durata = Double(campioni.count) / 16_000
    let impronte = try await gestore.embedSpans(
        audioSource: ArrayAudioSampleSource(samples: campioni),
        spans: [0..<durata]
    )
    let impronta = impronte.first ?? []
    risultati[URL(fileURLWithPath: percorso).deletingPathExtension().lastPathComponent] = impronta
    FileHandle.standardError.write(Data("FluidAudio · \(percorso): \(impronta.count) valori\n".utf8))
}
let codificatore = JSONEncoder()
codificatore.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try codificatore.encode(risultati))
