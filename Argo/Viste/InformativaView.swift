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
                    punto("megaphone", "Avvisa i partecipanti che la riunione viene registrata e trascritta con l'AI.")
                    punto("iphone", "Audio, trascrizione e verbale vengono elaborati solo su questo iPhone, senza servizi cloud.")
                    punto("trash", "Se l'opzione è attiva in Impostazioni, l'audio viene eliminato appena trascritto.")
                    punto("checkmark.shield", "Il verbale generato dall'AI va riletto prima di condividerlo.")
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

    private func punto(_ icona: String, _ testo: String) -> some View {
        Label {
            Text(testo)
        } icon: {
            Image(systemName: icona).foregroundStyle(.tint)
        }
    }
}
