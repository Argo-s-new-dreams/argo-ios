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
    @State private var erroreImport: String?

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if sessioni.isEmpty {
                    ContentUnavailableView(
                        "Nessuna sessione",
                        systemImage: "waveform",
                        description: Text("Registra una riunione: trascrizione e verbale vengono creati sul tuo iPhone, senza cloud.")
                    )
                } else {
                    List {
                        ForEach(sessioni) { sessione in
                            NavigationLink(value: sessione) {
                                RigaSessione(sessione: sessione)
                            }
                        }
                        .onDelete(perform: elimina)
                    }
                }
            }
            .navigationTitle("Argo")
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
                Button {
                    mostraRegistra = true
                } label: {
                    Label("Registra", systemImage: "record.circle")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .fullScreenCover(isPresented: $mostraRegistra) {
                RegistraView { nomeFile, durata in
                    let nuova = Sessione(
                        titolo: "Riunione del \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                        lingua: lingua, durata: durata, nomeFileAudio: nomeFile
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

    private func elimina(_ indici: IndexSet) {
        for indice in indici {
            let sessione = sessioni[indice]
            sessione.eliminaAudio()
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
        case .completata: .green
        case .errore: .orange
        default: .secondary
        }
    }
}
