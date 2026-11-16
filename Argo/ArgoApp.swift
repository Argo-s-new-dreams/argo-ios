import SwiftUI
import SwiftData

@main
struct ArgoApp: App {
    var body: some Scene {
        WindowGroup {
            ElencoSessioniView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Sessione.self)
    }
}
