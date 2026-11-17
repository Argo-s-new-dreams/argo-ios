// impronta-fluid file1.wav [file2.wav …] > fluid.json
// Per ogni file (una sola persona che parla) stampa l'impronta calcolata come fa Argo per iPhone
// nel profilo voce: DiarizerManager.extractEmbedding sui campioni a 16 kHz.
import Foundation
import FluidAudio

let file = Array(CommandLine.arguments.dropFirst())
guard !file.isEmpty else {
    FileHandle.standardError.write(Data("uso: impronta-fluid file.wav [altri…]\n".utf8))
    exit(1)
}

let modelli = try await DiarizerModels.downloadIfNeeded()
let diarizzatore = DiarizerManager()
try await diarizzatore.initialize(models: modelli)

var risultati: [String: [Float]] = [:]
for percorso in file {
    let campioni = try AudioConverter().resampleAudioFile(path: percorso)
    let impronta: [Float] = try await diarizzatore.extractEmbedding(campioni)
    risultati[URL(fileURLWithPath: percorso).deletingPathExtension().lastPathComponent] = impronta
    FileHandle.standardError.write(Data("FluidAudio · \(percorso): \(impronta.count) valori\n".utf8))
}
let codificatore = JSONEncoder()
codificatore.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try codificatore.encode(risultati))
