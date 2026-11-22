import SwiftUI
import SwiftData

@main
struct ArgoApp: App {
    @State private var esitoImport: String?

    var body: some Scene {
        WindowGroup {
#if DEBUG
            // Modalità vetrina per gli screenshot dell'App Store (solo build Debug, vedi Vetrina.swift)
            if let schermata = Vetrina.schermata {
                VetrinaView(schermata: schermata)
            } else {
                principale
            }
#else
            principale
#endif
        }
        .modelContainer(for: Sessione.self)
    }

    private var principale: some View {
        ElencoSessioniView()
            .preferredColorScheme(.dark)
            // «Apri con Argo» da AirDrop o File: anagrafe voci esportata da Argo desktop.
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "argovoci" else { return }
                do {
                    let anagrafe = try ArchivioAnagrafe.importa(da: url)
                    let nomi = anagrafe.voci.map(\.nome).joined(separator: ", ")
                    esitoImport = String(localized: "Anagrafe importata: \(anagrafe.voci.count) voci (\(nomi)).")
                } catch {
                    esitoImport = error.localizedDescription
                }
            }
            .alert("Anagrafe voci", isPresented: .constant(esitoImport != nil)) {
                Button("OK") { esitoImport = nil }
            } message: {
                Text(esitoImport ?? "")
            }
    }
}
