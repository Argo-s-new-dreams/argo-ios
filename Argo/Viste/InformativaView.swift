import SwiftUI

/// Promemoria di trasparenza prima di ogni registrazione (GDPR / AI Act).
struct InformativaView: View {
    let alConferma: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("Prima di registrare")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 14) {
                    punto("megaphone", "Avvisa chi hai di fronte che la conversazione viene registrata, trascritta con l'AI e divisa per voci, e chiedi il consenso.")
                    punto("iphone", "Audio e trascrizione restano su questo iPhone. La relazione la scrive l'iPhone o il tuo Mac in rete locale: mai servizi cloud.")
                    punto("trash", "Per impostazione predefinita l'audio viene eliminato appena trascritto: restano testo e foto.")
                    punto("checkmark.shield", "La relazione generata dall'AI va riletta prima di condividerla.")
                }

                Button(action: alConferma) {
                    Text("Ho informato i partecipanti · Registra")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 12)
            }
            .padding(24)
        }
    }

    private func punto(_ icona: String, _ testo: LocalizedStringKey) -> some View {
        Label {
            Text(testo)
        } icon: {
            Image(systemName: icona).foregroundStyle(.tint)
        }
    }
}
