import SwiftUI
import UIKit

/// Fotocamera di sistema, solo foto. Non tocca la registrazione in corso.
struct FotocameraView: UIViewControllerRepresentable {
    let alloScatto: (UIImage) -> Void
    @Environment(\.dismiss) private var chiudi

    static var disponibile: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let genitore: FotocameraView
        init(_ genitore: FotocameraView) { self.genitore = genitore }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let immagine = info[.originalImage] as? UIImage {
                genitore.alloScatto(immagine)
            }
            genitore.chiudi()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            genitore.chiudi()
        }
    }
}

/// Foglio di condivisione di sistema (AirDrop, File, Mail…).
struct CondivisioneView: UIViewControllerRepresentable {
    let elementi: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: elementi, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
