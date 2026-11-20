import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var confermaEliminaVoce = false
    @State private var anagrafe = ArchivioAnagrafe.carica()
    @State private var abbinamento = Ponte.abbinamento
    @State private var mostraCollega = false
    @State private var sincronizzazione: String?
    @State private var sincronizzando = false
    @AppStorage("eliminaDopoInvio") private var eliminaDopoInvio = false
    @Environment(\.modelContext) private var contesto
    @State private var mostraImportaAnagrafe = false
    @State private var erroreAnagrafe: String?
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

                sezionePonte

                sezioneVoce

                sezioneAnagrafe

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
                    NavigationLink("Licenze e riconoscimenti") { LicenzeView() }
                }
            }
            .fileImporter(isPresented: $mostraImportaAnagrafe, allowedContentTypes: [.anagrafeVoci, .json]) { esito in
                do {
                    anagrafe = try ArchivioAnagrafe.importa(da: esito.get())
                    erroreAnagrafe = nil
                } catch {
                    erroreAnagrafe = error.localizedDescription
                }
            }
            .sheet(isPresented: $mostraCollega) {
                CollegaArgoView { nuovo in
                    abbinamento = nuovo
                    Task { await sincronizza() }
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
                    .foregroundStyle(StileArgo.ok)
                Button("Registra di nuovo", systemImage: "mic") { mostraProfiloVoce = true }
                Button("Elimina il profilo voce", systemImage: "trash", role: .destructive) {
                    confermaEliminaVoce = true
                }
                .confirmationDialog("Eliminare il profilo voce?", isPresented: $confermaEliminaVoce,
                                    titleVisibility: .visible) {
                    Button("Elimina", role: .destructive) {
                        ArchivioVoce.elimina()
                        self.profiloVoce = nil
                    }
                } message: {
                    Text("Argo non ti riconoscerà più negli incontri finché non registri di nuovo la tua voce.")
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

    // MARK: Argo sul computer (Ponte)

    private var sezionePonte: some View {
        Section {
            if let abbinamento {
                LabeledContent("Collegato a", value: abbinamento.nome)
                if let ultima = abbinamento.ultimaSincronizzazione {
                    LabeledContent("Ultima sincronizzazione", value: ultima.formatted(date: .abbreviated, time: .shortened))
                }
                Button {
                    Task { await sincronizza() }
                } label: {
                    HStack {
                        Label("Sincronizza ora", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if sincronizzando { ProgressView() }
                    }
                }
                .disabled(sincronizzando)
                if let sincronizzazione {
                    Text(sincronizzazione).font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Elimina dall'iPhone dopo l'invio", isOn: $eliminaDopoInvio)
                Button("Scollega", systemImage: "link.badge.plus", role: .destructive) {
                    Ponte.scollega()
                    self.abbinamento = nil
                }
            } else {
                Button("Collega (inquadra il QR sul computer)", systemImage: "qrcode.viewfinder") {
                    mostraCollega = true
                }
            }
        } header: {
            Text("Argo sul computer")
        } footer: {
            Text("Canale cifrato in rete locale con Argo desktop: gli incontri trascritti partono da soli quando sei sulla stessa rete e Argo è aperto; l'anagrafe voci scelta sul computer arriva qui. Niente cloud.")
        }
    }

    private func sincronizza() async {
        sincronizzando = true
        let esito = await Ponte.sincronizza(contesto)
        sincronizzando = false
        abbinamento = Ponte.abbinamento
        anagrafe = ArchivioAnagrafe.carica()
        sincronizzazione = esito ?? (abbinamento?.ultimaSincronizzazione != nil
            ? "Tutto aggiornato." : "Argo sul computer non raggiungibile: deve essere aperto e sulla stessa rete.")
    }

    // MARK: Anagrafe voci (da Argo desktop)

    private var sezioneAnagrafe: some View {
        Section {
            if let anagrafe {
                DisclosureGroup("\(anagrafe.voci.count) voci · importata il \((anagrafe.importata ?? .now).formatted(date: .abbreviated, time: .shortened))") {
                    ForEach(anagrafe.voci, id: \.nome) { voce in
                        LabeledContent(voce.nome, value: voce.campioni.map { "\($0) campioni" } ?? "")
                    }
                }
                Button("Aggiorna da file…", systemImage: "arrow.down.doc") { mostraImportaAnagrafe = true }
                Button("Elimina l'anagrafe dall'iPhone", systemImage: "trash", role: .destructive) {
                    ArchivioAnagrafe.elimina()
                    self.anagrafe = nil
                }
            } else {
                Button("Importa da file…", systemImage: "arrow.down.doc") { mostraImportaAnagrafe = true }
            }
            if let erroreAnagrafe {
                Label(erroreAnagrafe, systemImage: "exclamationmark.triangle").foregroundStyle(StileArgo.avviso)
            }
        } header: {
            Text("Anagrafe voci da Argo desktop")
        } footer: {
            Text("Sul computer: Argo › Voci › 📱 Per iPhone…; arriva da sola con il collegamento, oppure via AirDrop («Apri con Argo»). Negli incontri le voci note prendono il loro nome. Dati biometrici: restano su questo iPhone e non vengono mai esportati.")
        }
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
                    .foregroundStyle(StileArgo.ok)
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
                    .foregroundStyle(StileArgo.ok)
            case .errore(let messaggio)?:
                Label(messaggio, systemImage: "xmark.octagon")
                    .foregroundStyle(StileArgo.avviso)
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
