import SwiftUI

/// Registrazione guidata della propria voce (una volta sola).
struct ProfiloVoceView: View {
    let nome: String
    let alSalvataggio: (ProfiloVoce) -> Void

    @Environment(\.dismiss) private var chiudi
    @State private var registratore = Registratore()
    @State private var stato: Stato = .pronto

    private enum Stato: Equatable { case pronto, registrazione, calcolo, errore(String) }
    private let durataMinima: TimeInterval = 20

    private let testo = """
    Buongiorno, sono qui per registrare la mia voce. Argo la userà per riconoscermi \
    durante le riunioni e le fiere, distinguendomi dalle persone con cui parlo. \
    Leggo questo testo con calma, con il mio tono di sempre, come se fossi allo stand \
    a spiegare un progetto a un cliente. Mi piace la tecnologia quando semplifica il lavoro, \
    e oggi provo a insegnare a un telefono a riconoscere chi sta parlando.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Leggi ad alta voce, con il tuo tono normale, in un posto tranquillo.")
                        .foregroundStyle(.secondary)

                    Text(testo)
                        .font(.title3)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))

                    switch stato {
                    case .pronto:
                        Button {
                            Task { await avvia() }
                        } label: {
                            Label("Inizia a leggere", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)

                    case .registrazione:
                        VStack(spacing: 12) {
                            ProgressView(value: min(registratore.durata, durataMinima), total: durataMinima)
                            Text(registratore.durata < durataMinima
                                 ? "Continua a leggere… \(Int(durataMinima - registratore.durata)) s"
                                 : "Perfetto, puoi fermarti")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button {
                                Task { await concludi() }
                            } label: {
                                Label("Fine", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(registratore.durata < durataMinima)
                        }

                    case .calcolo:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Calcolo l'impronta della tua voce (la prima volta scarico il modello)…")
                                .foregroundStyle(.secondary)
                        }

                    case .errore(let messaggio):
                        Label(messaggio, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(StileArgo.avviso)
                        Button("Riprova") { stato = .pronto }
                    }

                    Label("L'audio viene cancellato subito: resta solo un'impronta numerica, salvata su questo iPhone e mai esportata.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("La mia voce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        registratore.annulla()
                        chiudi()
                    }
                }
            }
        }
        .interactiveDismissDisabled(stato == .registrazione || stato == .calcolo)
    }

    private func avvia() async {
        guard await Registratore.chiediPermessoMicrofono() else {
            stato = .errore("Serve l'accesso al microfono.")
            return
        }
        do {
            try registratore.avvia()
            stato = .registrazione
        } catch {
            stato = .errore(error.localizedDescription)
        }
    }

    private func concludi() async {
        guard let esito = registratore.ferma() else { return }
        stato = .calcolo
        let url = Archivio.cartellaAudio.appending(path: esito.nomeFile)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let impronta = try await RiconoscitoreVoce.impronta(file: url)
            let profilo = ProfiloVoce(nome: nome, impronta: impronta, creato: .now)
            try ArchivioVoce.salva(profilo)
            alSalvataggio(profilo)
            chiudi()
        } catch {
            stato = .errore(error.localizedDescription)
        }
    }
}
