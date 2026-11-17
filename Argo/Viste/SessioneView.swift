import SwiftUI

struct SessioneView: View {
    @Bindable var sessione: Sessione
    @AppStorage("eliminaAudio") private var eliminaAudio = true

    @State private var fase: String?
    @State private var trascrizioneAperta = false

    private var inCorso: Bool { fase != nil }

    var body: some View {
        List {
            Section {
                TextField("Titolo", text: $sessione.titolo, axis: .vertical)
                    .font(.title3.weight(.semibold))
                LabeledContent("Data", value: sessione.creata.formatted(date: .long, time: .shortened))
                if sessione.durata > 0 {
                    LabeledContent("Durata", value: Formato.durata(sessione.durata))
                }
                LabeledContent("Audio", value: sessione.nomeFileAudio == nil ? "eliminato" : "sul dispositivo")
            }

            if let fase {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(fase).foregroundStyle(.secondary)
                    }
                }
            }

            if !inCorso, let messaggio = sessione.messaggioErrore {
                Section {
                    Label(messaggio, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if !inCorso, let avviso = sessione.avviso {
                Section {
                    Label(avviso, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if !sessione.riassunto.isEmpty {
                Section("Riassunto") {
                    Text(sessione.riassunto)
                }
            }

            if !sessione.puntiChiave.isEmpty {
                Section("Punti chiave") {
                    ForEach(sessione.puntiChiave, id: \.self) { punto in
                        Label(punto, systemImage: "circle.fill")
                            .labelStyle(PuntoElenco())
                    }
                }
            }

            if !sessione.azioni.isEmpty {
                Section("Azioni") {
                    ForEach(sessione.azioni) { azione in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(azione.descrizione)
                            let dettagli = [azione.responsabile, azione.scadenza.map { "entro \($0)" }]
                                .compactMap { $0 }.filter { !$0.isEmpty }
                            if !dettagli.isEmpty {
                                Text(dettagli.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !sessione.trascrizione.isEmpty {
                Section {
                    DisclosureGroup("Trascrizione", isExpanded: $trascrizioneAperta) {
                        Text(sessione.trascrizione)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }

            if sessione.stato != .completata, puoElaborare, !inCorso {
                Section {
                    Button(
                        sessione.trascrizione.isEmpty ? "Trascrivi e crea il verbale" : "Crea il verbale",
                        systemImage: "sparkles"
                    ) {
                        Task { await elabora() }
                    }
                }
            }

            if let motore = sessione.motoreVerbale, sessione.stato == .completata {
                Section {
                    Text("Verbale scritto da \(motore). Rileggilo prima di condividerlo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sessione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sessione.stato == .completata || sessione.stato == .trascritta {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: sessione.markdown, subject: Text(sessione.titolo)) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            // Appena registrata: parte da sola.
            if sessione.stato == .registrata { await elabora() }
        }
    }

    private var puoElaborare: Bool {
        !sessione.trascrizione.isEmpty || sessione.urlAudio != nil
    }

    private func elabora() async {
        fase = "Preparo…"
        await Elaborazione.esegui(sessione, eliminaAudioDopo: eliminaAudio) { fase = $0 }
        fase = nil
    }
}

private struct PuntoElenco: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(.tint)
            configuration.title
        }
    }
}
