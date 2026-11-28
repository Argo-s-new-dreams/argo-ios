import SwiftUI

struct SessioneView: View {
    @Bindable var sessione: Sessione
    @AppStorage("eliminaAudio") private var eliminaAudio = true

    @State private var faseInvio: String?
    @State private var cronologiaAperta = false
    @State private var fotoAperta: FotoSessione?
    @State private var pacchetto: FileDaCondividere?
    @State private var erroreEsportazione: String?
    @State private var invioInCorso = false

    /// La fase dell'elaborazione arriva da Elaborazione (continua anche se esci da questa schermata).
    private var fase: String? { faseInvio ?? Elaborazione.fasi.valori[sessione.id] }
    private var inCorso: Bool { fase != nil }

    var body: some View {
        ScrollViewReader { lettore in
            List {
                Section {
                    TextField("Titolo", text: $sessione.titolo, axis: .vertical)
                        .font(.title3.weight(.semibold))
                    LabeledContent("Data", value: sessione.creata.formatted(date: .long, time: .shortened))
                    if sessione.durata > 0 {
                        LabeledContent("Durata", value: Formato.durata(sessione.durata))
                    }
                    LabeledContent("Audio", value: sessione.nomeFileAudio == nil ? String(localized: "eliminato") : String(localized: "sul dispositivo"))
                }

                // Stile Argo: l'azione principale si vede subito, non in fondo dopo la trascrizione
                if puoElaborare, !inCorso, sessione.stato != .completata {
                    Section {
                        Button(etichettaElabora, systemImage: "sparkles") {
                            elabora()
                        }
                        .fontWeight(.semibold)
                    }
                }

                if let fase {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(fase).foregroundStyle(.secondary)
                        }
                    } footer: {
                        if faseInvio == nil {
                            Text("Puoi tornare all'elenco: Argo continua. Tieni l'app aperta finché finisce: lo schermo resta acceso da solo.")
                        }
                    }
                }

                if !inCorso, let messaggio = sessione.messaggioErrore {
                    Section {
                        Label(messaggio, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(StileArgo.avviso)
                    }
                }

                if !inCorso, let avviso = sessione.avviso {
                    Section {
                        Label(avviso, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if !sessione.riassunto.isEmpty {
                    Section("Riassunto") { Text(sessione.riassunto) }
                }

                if !sessione.contatti.isEmpty {
                    Section("Contatti") {
                        ForEach(sessione.contatti) { contatto in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contatto.nome).font(.headline)
                                let dettagli = [contatto.ruolo, contatto.azienda].compactMap { $0 }.filter { !$0.isEmpty }
                                if !dettagli.isEmpty {
                                    Text(dettagli.joined(separator: " · ")).font(.subheadline)
                                }
                                let recapiti = [contatto.email, contatto.telefono].compactMap { $0 }.filter { !$0.isEmpty }
                                if !recapiti.isEmpty {
                                    Text(recapiti.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if let note = contatto.note, !note.isEmpty {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !sessione.puntiChiave.isEmpty {
                    Section("Punti chiave") {
                        ForEach(sessione.puntiChiave, id: \.self) { punto in
                            Label(punto, systemImage: "circle.fill").labelStyle(PuntoElenco())
                        }
                    }
                }

                if !sessione.azioni.isEmpty {
                    Section("Azioni") {
                        ForEach(sessione.azioni) { azione in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(azione.descrizione)
                                let dettagli = [azione.responsabile, azione.scadenza.map { String(localized: "entro \($0)") }]
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

                // Taccuino Plus (laboratorio): azioni dettate a Peppino, si confermano sul computer
                if !sessione.azioniCRM.isEmpty {
                    Section {
                        ForEach(sessione.azioniCRM) { azione in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: azione.riepilogo)
                                if !azione.frase.isEmpty {
                                    Text(verbatim: "«\(azione.frase)»").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: "Azioni per il CRM · in coda")
                    } footer: {
                        Text(verbatim: sessione.inviataAdArgo == nil
                             ? "Invia questo incontro ad Argo sul computer: lì scegli il record in Dynamics e confermi."
                             : "Consegnate ad Argo sul computer: confermale in Incontri › 📋 Azioni CRM.")
                    }
                }

                if !sessione.parlanti.isEmpty {
                    Section {
                        ForEach(sessione.parlanti, id: \.self) { id in
                            HStack {
                                Circle().fill(Colori.parlante(id)).frame(width: 10, height: 10)
                                TextField("Parlante \(id.dropFirst())", text: nomeBinding(id))
                            }
                        }
                    } header: {
                        Text("Partecipanti")
                    } footer: {
                        Text("Dai un nome alle voci (es. «Io», «Mario Rossi»): li userà la relazione. Poi tocca «Rifai la relazione».")
                    }
                }

                if !sessione.foto.isEmpty {
                    Section("Foto") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(sessione.foto.sorted { $0.secondo < $1.secondo }) { foto in
                                    Button { fotoAperta = foto } label: {
                                        VStack(spacing: 4) {
                                            MiniaturaFoto(foto: foto).frame(width: 84, height: 84)
                                            Text(Formato.durata(foto.secondo))
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if sessione.haTrascrizione {
                    Section {
                        DisclosureGroup("Trascrizione", isExpanded: $cronologiaAperta) {
                            if sessione.segmenti.isEmpty {
                                Text(sessione.trascrizione).font(.callout).textSelection(.enabled)
                            } else {
                                ForEach(sessione.cronologia) { voce in
                                    RigaCronologia(voce: voce, sessione: sessione) { fotoAperta = $0 }
                                }
                            }
                        }
                    }
                    .id("trascrizione")
                }

                if puoElaborare, !inCorso, sessione.stato == .completata {
                    Section {
                        Button(etichettaElabora, systemImage: "sparkles") {
                            elabora()
                        }
                    }
                }

                if let inviata = sessione.inviataAdArgo {
                    Section {
                        Label("Inviato ad Argo sul computer il \(inviata.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "desktopcomputer")  // mai un'icona «cloud»: non passa da nessun cloud
                            .font(.footnote)
                            .foregroundStyle(StileArgo.ok)
                    }
                }

                if let motore = sessione.motoreVerbale, sessione.stato == .completata {
                    Section {
                        Text("Relazione scritta da \(motore). Rileggila prima di condividerla.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
#if DEBUG
            // Modalità vetrina: trascrizione aperta o foto in primo piano per gli screenshot.
            .task {
                switch Vetrina.schermata {
                case .some(.trascrizione):
                    cronologiaAperta = true
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation { lettore.scrollTo("trascrizione", anchor: .top) }
                case .some(.foto):
                    try? await Task.sleep(for: .milliseconds(500))
                    fotoAperta = sessione.foto.sorted { $0.secondo < $1.secondo }.first
                default:
                    break
                }
            }
#endif
        }
        .navigationTitle("Incontro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sessione.haTrascrizione {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if Ponte.abbinamento != nil {
                            Button("Invia ad Argo sul computer", systemImage: "desktopcomputer.and.arrow.down") {
                                Task { await inviaAdArgo() }
                            }
                        }
                        Button("Pacchetto (AirDrop, File…)", systemImage: "shippingbox") {
                            esporta()
                        }
                        ShareLink(item: sessione.markdown, subject: Text(sessione.titolo)) {
                            Label("Solo testo della relazione", systemImage: "doc.plaintext")
                        }
                    } label: {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                    .disabled(inCorso || invioInCorso)
                }
            }
        }
        .sheet(item: $fotoAperta) { foto in
            DettaglioFotoView(foto: foto)
        }
        .sheet(item: $pacchetto) { file in
            CondivisioneView(elementi: [file.url])
        }
        .alert("Esportazione non riuscita", isPresented: .constant(erroreEsportazione != nil)) {
            Button("OK") { erroreEsportazione = nil }
        } message: {
            Text(erroreEsportazione ?? "")
        }
        .task {
            // Appena registrata: parte da sola (in un lavoro che non si ferma se esci dalla schermata).
            if sessione.stato == .registrata { elabora() }
        }
    }

    private var puoElaborare: Bool {
        sessione.haTrascrizione || sessione.urlAudio != nil
    }

    private var etichettaElabora: String {
        if !sessione.haTrascrizione { return String(localized: "Trascrivi e crea la relazione") }
        return sessione.stato == .completata ? String(localized: "Rifai la relazione") : String(localized: "Crea la relazione")
    }

    private func nomeBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { sessione.nomiParlanti[id] ?? "" },
            set: { sessione.nomiParlanti[id] = $0 }
        )
    }

    private func elabora() {
        Elaborazione.avvia(sessione, eliminaAudioDopo: eliminaAudio)
    }

    private func inviaAdArgo() async {
        invioInCorso = true
        faseInvio = String(localized: "Invio ad Argo sul computer…")
        do {
            try await Ponte.invia(sessione)
        } catch {
            erroreEsportazione = error.localizedDescription
        }
        faseInvio = nil
        invioInCorso = false
    }

    private func esporta() {
        do {
            pacchetto = FileDaCondividere(url: try Esportatore.pacchetto(di: sessione))
        } catch {
            erroreEsportazione = error.localizedDescription
        }
    }
}

private struct FileDaCondividere: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct RigaCronologia: View {
    let voce: VoceCronologia
    let sessione: Sessione
    let apriFoto: (FotoSessione) -> Void

    var body: some View {
        switch voce {
        case .parole(let segmento):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let parlante = segmento.parlante {
                        Text(sessione.nome(di: parlante) ?? parlante)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Colori.parlante(parlante))
                    }
                    Text(Formato.durata(segmento.inizio))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(segmento.testo).font(.callout).textSelection(.enabled)
            }
        case .foto(let foto):
            Button { apriFoto(foto) } label: {
                HStack(spacing: 10) {
                    MiniaturaFoto(foto: foto).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📷 \(Formato.durata(foto.secondo))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(foto.testoOCR.isEmpty ? String(localized: "Foto") : foto.testoOCR)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DettaglioFotoView: View {
    let foto: FotoSessione
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let immagine = UIImage(contentsOfFile: foto.url.path) {
                        Image(uiImage: immagine)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !foto.riferimenti.isEmpty {
                        Text("Riferimenti").font(.headline)
                        ForEach(foto.riferimenti, id: \.self) { Text($0).textSelection(.enabled) }
                    }
                    if !foto.testoOCR.isEmpty {
                        Text("Testo letto").font(.headline)
                        Text(foto.testoOCR).font(.callout).textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("Foto a \(Formato.durata(foto.secondo))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { chiudi() } }
            }
        }
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

enum Colori {
    private static let tavolozza: [Color] = StileArgo.parlanti  // stessi colori dei parlanti di Argo sul computer

    static func parlante(_ id: String) -> Color {
        let numero = max(1, Int(id.dropFirst()) ?? 1)
        return tavolozza[(numero - 1) % tavolozza.count]
    }
}
