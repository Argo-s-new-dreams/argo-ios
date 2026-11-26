import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ElencoSessioniView: View {
    @Environment(\.modelContext) private var contesto
    @Query(sort: \Sessione.creata, order: .reverse) private var sessioni: [Sessione]
    @AppStorage("lingua") private var lingua = "it-IT"

    @State private var percorso: [Sessione] = []
    @State private var mostraRegistra = false
    @State private var mostraImpostazioni = false
    @State private var mostraImporta = false
    @State private var mostraLive = false
    @State private var laboratorio = false
    @State private var comandi = ComandiArgo.condivisi
    @State private var erroreImport: String?
    @State private var esitoPonte: String?
    @State private var daEliminare: IndexSet?
    @Environment(\.scenePhase) private var fase

    /// «Ehi Siri, registra con Argo»: apre la registrazione (con l'informativa da confermare).
    private func apriDaSiri() {
        guard comandi.registra else { return }
        comandi.registra = false
        mostraRegistra = true
    }

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if sessioni.isEmpty {
                    ContentUnavailableView(
                        "Nessun incontro",
                        systemImage: "waveform",
                        description: Text("Tocca «Registra» qui sotto: durante l'incontro puoi scattare foto a biglietti da visita e documenti. Trascrizione, voci e testo delle foto vengono elaborati sul tuo iPhone.")
                    )
                } else {
                    List {
                        if !soloSuIPhone.isEmpty {
                            Section { avvisoSoloSuIPhone }
                        }
                        ForEach(sessioni) { sessione in
                            NavigationLink(value: sessione) {
                                RigaSessione(sessione: sessione)
                            }
                        }
                        .onDelete { daEliminare = $0 }
                    }
                    .refreshable { await sincronizza() }
                    .confirmationDialog("Eliminare l'incontro?",
                                        isPresented: Binding(get: { daEliminare != nil },
                                                             set: { if !$0 { daEliminare = nil } }),
                                        titleVisibility: .visible) {
                        Button("Elimina", role: .destructive) {
                            if let indici = daEliminare { elimina(indici) }
                            daEliminare = nil
                        }
                    } message: {
                        Text("Trascrizione, foto e relazione vengono cancellate da questo iPhone. Se non l'hai inviato ad Argo sul computer, non si possono recuperare.")
                    }
                }
            }
            .navigationTitle("Argo")
            .safeAreaInset(edge: .top) {
                if let esitoPonte {
                    Label(esitoPonte, systemImage: "desktopcomputer")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Quando Argo torna in primo piano: se il computer è raggiungibile, sincronizza da solo.
            .onChange(of: fase) { _, nuova in
                if nuova == .active { Task { await sincronizza() } }
            }
            .task {
#if DEBUG
                // Modalità vetrina: alcune schermate partono già dentro l'incontro principale.
                if Vetrina.apreIncontro, percorso.isEmpty, let principale = sessioni.first {
                    percorso = [principale]
                }
#endif
                await sincronizza()
            }
            .navigationDestination(for: Sessione.self) { SessioneView(sessione: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Impostazioni", systemImage: "gearshape") { mostraImpostazioni = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importa audio", systemImage: "square.and.arrow.down") { mostraImporta = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        mostraRegistra = true
                    } label: {
                        Label("Registra", systemImage: "record.circle")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    // Argo Live (laboratorio): solo nelle build di prova (Xcode e TestFlight), mai nell'App Store
                    if laboratorio {
                        Button {
                            mostraLive = true
                        } label: {
                            Label("Parla con Argo", systemImage: "waveform")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .task {
                laboratorio = await Laboratorio.attivo()
                apriDaSiri()
            }
            .onChange(of: comandi.registra) { _, _ in apriDaSiri() }
            .fullScreenCover(isPresented: $mostraLive) {
                NavigationStack {
                    LiveView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Chiudi", systemImage: "xmark") { mostraLive = false }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            }
            .fullScreenCover(isPresented: $mostraRegistra) {
                RegistraView { nomeFile, durata, foto in
                    let nuova = Sessione(
                        titolo: String(localized: "Incontro del \(Date.now.formatted(date: .abbreviated, time: .shortened))"),
                        lingua: lingua, durata: durata, nomeFileAudio: nomeFile, foto: foto
                    )
                    contesto.insert(nuova)
                    percorso = [nuova]
                }
            }
            .sheet(isPresented: $mostraImpostazioni) { ImpostazioniView() }
            .fileImporter(isPresented: $mostraImporta, allowedContentTypes: [.audio]) { esito in
                importa(esito)
            }
            .alert("Importazione non riuscita", isPresented: .constant(erroreImport != nil)) {
                Button("OK") { erroreImport = nil }
            } message: {
                Text(erroreImport ?? "")
            }
        }
    }

    /// Incontri che esistono solo su questo iPhone: se l'app viene eliminata (o reinstallata con un'altra
    /// firma, per esempio passando dal Personal Team al team a pagamento) si perdono.
    private var soloSuIPhone: [Sessione] { sessioni.filter { $0.inviataAdArgo == nil } }

    private var avvisoSoloSuIPhone: some View {
        let numero = soloSuIPhone.count
        let daTrascrivere = soloSuIPhone.filter { $0.stato != .trascritta && $0.stato != .completata }.count
        let abbinato = Ponte.abbinamento != nil
        var testo = numero == 1 ? String(localized: "1 incontro è solo su questo iPhone.") : String(localized: "\(numero) incontri sono solo su questo iPhone.")
        testo += " " + String(localized: "Se elimini o reinstalli l'app si perdono: prima inviali ad Argo sul computer.")
        if daTrascrivere > 0 {
            testo += " " + (daTrascrivere == 1 ? String(localized: "Uno va prima trascritto.") : String(localized: "\(daTrascrivere) vanno prima trascritti."))
        }
        if !abbinato { testo += " " + String(localized: "Collega il computer in Impostazioni › Argo sul computer.") }
        return VStack(alignment: .leading, spacing: 8) {
            Label(testo, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(StileArgo.avviso)
            if abbinato && numero > daTrascrivere {
                Button("Invia ora ad Argo sul computer", systemImage: "desktopcomputer") {
                    Task { await sincronizza() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func sincronizza() async {
        guard let esito = await Ponte.sincronizza(contesto) else { return }
        withAnimation { esitoPonte = esito }
        try? await Task.sleep(for: .seconds(5))
        withAnimation { esitoPonte = nil }
    }

    private func elimina(_ indici: IndexSet) {
        for indice in indici {
            let sessione = sessioni[indice]
            sessione.eliminaFile()
            contesto.delete(sessione)
        }
    }

    /// Importa un file audio (es. da Memo Vocali o File) copiandolo nella cartella di Argo.
    private func importa(_ esito: Result<URL, Error>) {
        do {
            let origine = try esito.get()
            let accesso = origine.startAccessingSecurityScopedResource()
            defer { if accesso { origine.stopAccessingSecurityScopedResource() } }

            let estensione = origine.pathExtension.isEmpty ? "m4a" : origine.pathExtension
            let nome = "argo-\(UUID().uuidString).\(estensione)"
            try FileManager.default.copyItem(at: origine, to: Archivio.cartellaAudio.appending(path: nome))

            let nuova = Sessione(
                titolo: origine.deletingPathExtension().lastPathComponent,
                lingua: lingua, durata: 0, nomeFileAudio: nome
            )
            contesto.insert(nuova)
            percorso = [nuova]
        } catch {
            erroreImport = error.localizedDescription
        }
    }
}

private struct RigaSessione: View {
    let sessione: Sessione

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sessione.titolo)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(sessione.creata.formatted(date: .abbreviated, time: .shortened))
                if sessione.durata > 0 {
                    Text("· \(Formato.durata(sessione.durata))")
                }
                if !sessione.foto.isEmpty {
                    Label("\(sessione.foto.count)", systemImage: "camera")
                        .labelStyle(.titleAndIcon)
                }
                if sessione.inviataAdArgo != nil {
                    Image(systemName: "desktopcomputer").foregroundStyle(StileArgo.ok)
                        .accessibilityLabel("Inviato ad Argo sul computer")
                }
                if sessione.parlanti.count > 1 {
                    Label("\(sessione.parlanti.count)", systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Image(systemName: icona)
                    .foregroundStyle(colore)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var icona: String {
        switch sessione.stato {
        case .registrata: "waveform"
        case .inTrascrizione: "hourglass"
        case .trascritta: "text.alignleft"
        case .completata: "checkmark.seal.fill"
        case .errore: "exclamationmark.triangle.fill"
        }
    }

    private var colore: Color {
        switch sessione.stato {
        case .completata: StileArgo.ok
        case .errore: StileArgo.avviso
        default: .secondary
        }
    }
}
