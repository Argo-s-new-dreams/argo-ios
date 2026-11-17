import SwiftUI
import VisionKit

/// Inquadra il QR mostrato da Argo desktop (Incontri › 📱 Collega iPhone…) e completa l'abbinamento.
struct CollegaArgoView: View {
    let alCollegamento: (AbbinamentoPonte) -> Void

    @Environment(\.dismiss) private var chiudi
    @State private var stato: Stato = .inquadra

    private enum Stato: Equatable { case inquadra, collegamento, errore(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch stato {
                case .inquadra:
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        LettoreQR { testo in
                            guard stato == .inquadra, testo.hasPrefix("argo-ponte:") else { return }
                            Task { await collega(testo) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "Fotocamera non disponibile",
                            systemImage: "qrcode.viewfinder",
                            description: Text("Consenti la fotocamera ad Argo in Impostazioni › Privacy › Fotocamera.")
                        )
                    }
                    Text("Sul computer apri **Argo › Incontri › 📱 Collega iPhone…** e inquadra il codice. iPhone e computer devono essere sulla stessa rete.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                case .collegamento:
                    Spacer()
                    ProgressView("Mi collego ad Argo sul computer…")
                    Spacer()

                case .errore(let messaggio):
                    Spacer()
                    Label(messaggio, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(StileArgo.avviso)
                        .padding()
                    Button("Riprova") { stato = .inquadra }
                        .buttonStyle(.glassProminent)
                    Spacer()
                }
            }
            .padding(.vertical)
            .navigationTitle("Collega Argo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() } }
            }
        }
    }

    private func collega(_ testo: String) async {
        stato = .collegamento
        do {
            let abbinamento = try await Ponte.abbina(qr: testo)
            alCollegamento(abbinamento)
            chiudi()
        } catch {
            stato = .errore(error.localizedDescription)
        }
    }
}

/// Lettore di QR di sistema (VisionKit), solo codici QR.
private struct LettoreQR: UIViewControllerRepresentable {
    let alRiconoscimento: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let lettore = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        lettore.delegate = context.coordinator
        try? lettore.startScanning()
        return lettore
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinatore) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinatore { Coordinatore(alRiconoscimento) }

    final class Coordinatore: NSObject, DataScannerViewControllerDelegate {
        let alRiconoscimento: (String) -> Void
        init(_ alRiconoscimento: @escaping (String) -> Void) { self.alRiconoscimento = alRiconoscimento }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for elemento in addedItems {
                if case .barcode(let codice) = elemento, let testo = codice.payloadStringValue {
                    alRiconoscimento(testo)
                }
            }
        }
    }
}
