import SwiftUI

struct ImpostazioniView: View {
    @Environment(\.dismiss) private var chiudi
    @AppStorage("lingua") private var lingua = "it-IT"
    @AppStorage("eliminaAudio") private var eliminaAudio = true
    @AppStorage("motore") private var motore = SceltaMotore.automatico.rawValue
    @AppStorage("ollamaIndirizzo") private var ollamaIndirizzo = ""
    @AppStorage("ollamaModello") private var ollamaModello = ""

    @State private var profiloVoce = ArchivioVoce.carica()
    @State private var nomeVoce = ArchivioVoce.carica()?.nome ?? "Io"
    @State private var mostraProfiloVoce = false
    @State private var modelliMac: [String] = []
    @State private var esitoProva: EsitoProva?
    @State private var provaInCorso = false

    private enum EsitoProva { case ok(Int), errore(String) }

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
                } header: {
                    Text("Trascrizione")
                } footer: {
                    Text("La trascrizione avviene sempre sull'iPhone. Il modello della lingua viene scaricato da Apple la prima volta.")
                }

                sezioneVoce

                sezioneVerbale

                if motore == SceltaMotore.mac.rawValue || motore == SceltaMotore.automatico.rawValue {
                    sezioneMac
                }

                Section {
                    Toggle("Elimina l'audio dopo la trascrizione", isOn: $eliminaAudio)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Come la modalità Live di Argo sul Mac: resta solo il testo, nessun archivio audio sul telefono.")
                }

                Section("Informazioni") {
                    LabeledContent("Versione", value: versione)
                    Link("Argo's New Dreams", destination: URL(string: "https://argosnewdreams.blog")!)
                }
            }
            .sheet(isPresented: $mostraProfiloVoce) {
                ProfiloVoceView(nome: nomeVoce.isEmpty ? "Io" : nomeVoce) { profiloVoce = $0 }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        aggiornaNomeVoce()
                        chiudi()
                    }
                }
            }
        }
    }

    // MARK: La mia voce

    private var sezioneVoce: some View {
        Section {
            TextField("Come ti chiami negli incontri", text: $nomeVoce)
                .onSubmit { aggiornaNomeVoce() }
            if let profiloVoce {
                Label("Voce registrata il \(profiloVoce.creato.formatted(date: .abbreviated, time: .omitted))",
                      systemImage: "person.wave.2.fill")
                    .foregroundStyle(.green)
                Button("Registra di nuovo", systemImage: "mic") { mostraProfiloVoce = true }
                Button("Elimina il profilo voce", systemImage: "trash", role: .destructive) {
                    ArchivioVoce.elimina()
                    self.profiloVoce = nil
                }
            } else {
                Button("Registra la mia voce (20 secondi)", systemImage: "mic.badge.plus") {
                    mostraProfiloVoce = true
                }
            }
        } header: {
            Text("La mia voce")
        } footer: {
            Text("Argo riconosce la tua voce negli incontri e la chiama con questo nome, separandola da quelle degli interlocutori. L'impronta vocale è un dato biometrico: resta solo su questo iPhone e non viene mai esportata.")
        }
    }

    private func aggiornaNomeVoce() {
        guard var profilo = profiloVoce else { return }
        let nome = nomeVoce.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        profilo.nome = nome
        try? ArchivioVoce.salva(profilo)
        profiloVoce = profilo
    }

    // MARK: Verbale

    private var sezioneVerbale: some View {
        Section {
            Picker("Chi scrive il verbale", selection: $motore) {
                ForEach(SceltaMotore.allCases) { scelta in
                    Text(scelta.nome).tag(scelta.rawValue)
                }
            }
            if let motivo = Verbalista.motivoAppleNonDisponibile {
                Label(motivo, systemImage: "iphone.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Apple Intelligence disponibile su questo iPhone", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Verbale")
        } footer: {
            Text("Automatico: Apple Intelligence se l'iPhone la supporta, altrimenti il tuo Mac con Ollama. Senza nessuno dei due ottieni comunque la trascrizione.")
        }
    }

    private var sezioneMac: some View {
        Section {
            TextField("nome-del-mac.local oppure 192.168.1.20", text: $ollamaIndirizzo)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task { await prova() }
            } label: {
                HStack {
                    Text("Prova connessione")
                    Spacer()
                    if provaInCorso { ProgressView() }
                }
            }
            .disabled(ollamaIndirizzo.isEmpty || provaInCorso)

            switch esitoProva {
            case .ok(let numero)?:
                Label("Mac raggiunto · \(numero) modelli installati", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .errore(let messaggio)?:
                Label(messaggio, systemImage: "xmark.octagon")
                    .foregroundStyle(.orange)
            case nil:
                EmptyView()
            }

            if !modelliMac.isEmpty {
                Picker("Modello", selection: $ollamaModello) {
                    ForEach(modelliMac, id: \.self) { Text($0).tag($0) }
                }
            } else if !ollamaModello.isEmpty {
                LabeledContent("Modello", value: ollamaModello)
            }
        } header: {
            Text("Il mio Mac (Ollama)")
        } footer: {
            Text("Mac e iPhone sulla stessa Wi-Fi. Sul Mac, Ollama deve accettare connessioni dalla rete locale. La trascrizione viaggia solo tra i tuoi dispositivi.")
        }
    }

    private func prova() async {
        provaInCorso = true
        defer { provaInCorso = false }
        guard let url = MotoreOllama.normalizza(ollamaIndirizzo) else {
            esitoProva = .errore("Indirizzo non valido.")
            return
        }
        do {
            modelliMac = try await MotoreOllama.modelli(su: url)
            esitoProva = .ok(modelliMac.count)
            if !modelliMac.contains(ollamaModello) {
                ollamaModello = modelliMac.first ?? ""
            }
        } catch {
            esitoProva = .errore(error.localizedDescription)
        }
    }
}
