import SwiftUI

/// Licenze e riconoscimenti dei componenti di terze parti (FluidAudio, modelli pyannote…).
/// Il testo completo sta in Risorse/LicenzeTerzeParti.txt, lo stesso descritto in LICENZE-TERZE-PARTI.md.
struct LicenzeView: View {
    private let testo: String = {
        guard let url = Bundle.main.url(forResource: "LicenzeTerzeParti", withExtension: "txt"),
              let contenuto = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "Testo delle licenze non trovato. Lo trovi su https://github.com/Argo-s-new-dreams/argo-ios/blob/main/LICENZE-TERZE-PARTI.md")
        }
        return contenuto
    }()

    var body: some View {
        ScrollView {
            Text(testo)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Licenze e riconoscimenti")
        .navigationBarTitleDisplayMode(.inline)
    }
}
