import AppIntents
import Observation

/// Comandi che arrivano da Siri (anche in auto, con CarPlay): l'app li legge e apre la schermata giusta.
@MainActor
@Observable
final class ComandiArgo {
    static let condivisi = ComandiArgo()
    var registra = false
}

/// «Ehi Siri, registra con Argo»: apre Argo sulla registrazione. L'informativa ai partecipanti si conferma
/// sempre sul telefono, come per ogni registrazione.
struct RegistraConArgo: AppIntent {
    static var title: LocalizedStringResource = "Registra"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ComandiArgo.condivisi.registra = true
        return .result()
    }
}

struct ScorciatoieArgo: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegistraConArgo(),
            phrases: [
                "Registra con \(.applicationName)",
                "Registra un incontro con \(.applicationName)",
            ],
            shortTitle: "Registra",
            systemImageName: "record.circle"
        )
    }
}
