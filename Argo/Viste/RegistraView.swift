import SwiftUI

/// Registrazione a schermo intero. Prima di partire chiede conferma dell'informativa,
/// come Argo sul Mac.
struct RegistraView: View {
    let alTermine: (_ nomeFile: String, _ durata: TimeInterval) -> Void

    @Environment(\.dismiss) private var chiudi
    @State private var registratore = Registratore()
    @State private var informativaConfermata = false
    @State private var errore: String?
    @State private var confermaAnnulla = false

    var body: some View {
        NavigationStack {
            Group {
                if informativaConfermata {
                    pannelloRegistrazione
                } else {
                    InformativaView {
                        Task { await avvia() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi", systemImage: "xmark") {
                        if registratore.staRegistrando { confermaAnnulla = true } else { chiudi() }
                    }
                }
            }
            .confirmationDialog("Scartare la registrazione?", isPresented: $confermaAnnulla, titleVisibility: .visible) {
                Button("Scarta", role: .destructive) {
                    registratore.annulla()
                    chiudi()
                }
            }
            .alert("Errore", isPresented: .constant(errore != nil)) {
                Button("OK") { errore = nil; chiudi() }
            } message: {
                Text(errore ?? "")
            }
        }
        .interactiveDismissDisabled(registratore.staRegistrando)
    }

    private var pannelloRegistrazione: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(Formato.durata(registratore.durata))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()

            MisuratoreLivello(livello: registratore.livello)
                .frame(height: 60)
                .padding(.horizontal)

            Text(registratore.inPausa ? "In pausa" : "Sto registrando · l'audio resta sul tuo iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 40) {
                Button {
                    registratore.inPausa ? registratore.riprendi() : registratore.pausa()
                } label: {
                    Image(systemName: registratore.inPausa ? "play.fill" : "pause.fill")
                        .font(.title)
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())

                Button {
                    if let esito = registratore.ferma() {
                        alTermine(esito.nomeFile, esito.durata)
                    }
                    chiudi()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .frame(width: 88, height: 88)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .clipShape(Circle())
            }
            .padding(.bottom, 40)
        }
    }

    private func avvia() async {
        guard await Registratore.chiediPermessoMicrofono() else {
            errore = "Serve l'accesso al microfono: lo trovi in Impostazioni › Privacy › Microfono."
            return
        }
        do {
            try registratore.avvia()
            informativaConfermata = true
        } catch {
            errore = error.localizedDescription
        }
    }
}

private struct MisuratoreLivello: View {
    let livello: Float

    var body: some View {
        GeometryReader { geo in
            let barre = 32
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barre, id: \.self) { i in
                    // profilo a campana: le barre centrali reagiscono di più
                    let distanza = abs(Double(i) - Double(barre - 1) / 2) / (Double(barre) / 2)
                    let altezza = max(4, geo.size.height * CGFloat(Double(livello) * (1 - distanza * 0.7)))
                    Capsule()
                        .fill(.tint)
                        .frame(height: altezza)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.1), value: livello)
        }
    }
}
