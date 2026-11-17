import SwiftUI
import SwiftData

@main
struct ArgoApp: App {
    @State private var esitoImport: String?

    var body: some Scene {
        WindowGroup {
            ElencoSessioniView()
                .preferredColorScheme(.dark)
                // «Apri con Argo» da AirDrop o File: anagrafe voci esportata da Argo desktop.
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "argovoci" else { return }
                    do {
                        let anagrafe = try ArchivioAnagrafe.importa(da: url)
                        esitoImport = "Anagrafe importata: \(anagrafe.voci.count) voci (\(anagrafe.voci.map(\.nome).joined(separator: ", ")))."
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
        .modelContainer(for: Sessione.self)
    }
}
