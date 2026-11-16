import SwiftUI

struct ImpostazioniView: View {
    @Environment(\.dismiss) private var chiudi
    @AppStorage("lingua") private var lingua = "it-IT"
    @AppStorage("eliminaAudio") private var eliminaAudio = true

    private var versione: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Lingua della riunione", selection: $lingua) {
                        ForEach(Trascrittore.lingueProposte, id: \.codice) { voce in
                            Text(voce.nome).tag(voce.codice)
                        }
                    }
                } footer: {
                    Text("Vale per le nuove registrazioni. Il modello della lingua viene scaricato da Apple la prima volta.")
                }

                Section {
                    Toggle("Elimina l'audio dopo la trascrizione", isOn: $eliminaAudio)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Come la modalità Live di Argo sul Mac: resta solo il testo, nessun archivio audio sul telefono.")
                }

                Section("Apple Intelligence") {
                    if let avviso = Verbalista.messaggioIndisponibilita {
                        Label(avviso, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Disponibile: il verbale viene creato sul dispositivo", systemImage: "checkmark.seal")
                            .foregroundStyle(.green)
                    }
                }

                Section("Informazioni") {
                    LabeledContent("Versione", value: versione)
                    LabeledContent("Elaborazione", value: "🔒 100% locale")
                    Link("Argo's New Dreams", destination: URL(string: "https://argosnewdreams.blog")!)
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { chiudi() }
                }
            }
        }
    }
}
