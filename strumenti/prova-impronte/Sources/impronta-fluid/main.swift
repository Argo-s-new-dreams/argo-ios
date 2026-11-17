// impronta-fluid uscita.json file1.wav [file2.wav …]
// Per ogni file (una sola persona che parla) stampa l'impronta calcolata come fa Argo per iPhone:
// pipeline offline di FluidAudio, `embedSpans` sull'intero audio (stesso tipo di vettori
// di `DiarizationResult.speakerDatabase`, usati per riconoscere le voci negli incontri).
import Foundation
import FluidAudio

// Il risultato va su file: la libreria scrive messaggi di diagnostica sullo standard output.
let argomenti = Array(CommandLine.arguments.dropFirst())
guard argomenti.count >= 2 else {
    FileHandle.standardError.write(Data("uso: impronta-fluid uscita.json file.wav [altri…]\n".utf8))
    exit(1)
}
let uscita = URL(fileURLWithPath: argomenti[0])
let file = Array(argomenti.dropFirst())

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
try codificatore.encode(risultati).write(to: uscita)
