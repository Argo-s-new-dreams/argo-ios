import SwiftUI
import AVFoundation
import UIKit

/// Fotocamera interna di Argo, solo video: NON tocca la sessione audio,
/// quindi la registrazione continua mentre scatti.
/// (La fotocamera di sistema, UIImagePickerController, interrompeva il microfono.)
@MainActor
@Observable
final class Fotocamera: NSObject {
    let sessione = AVCaptureSession()
    private let uscita = AVCapturePhotoOutput()
    private var continuazione: CheckedContinuation<UIImage?, Never>?
    private(set) var pronta = false
    private(set) var negata = false

    func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            negata = true
            return
        }
        if !pronta {
            sessione.beginConfiguration()
            sessione.sessionPreset = .photo
            // Il punto chiave: la cattura video non deve riconfigurare l'audio dell'app.
            sessione.automaticallyConfiguresApplicationAudioSession = false
            if let dispositivo = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let ingresso = try? AVCaptureDeviceInput(device: dispositivo),
               sessione.canAddInput(ingresso), sessione.canAddOutput(uscita) {
                sessione.addInput(ingresso)
                sessione.addOutput(uscita)
                pronta = true
            }
            sessione.commitConfiguration()
        }
        let sessione = self.sessione
        await Task.detached { sessione.startRunning() }.value
    }

    func ferma() {
        let sessione = self.sessione
        Task.detached { sessione.stopRunning() }
    }

    func scatta() async -> UIImage? {
        guard pronta, continuazione == nil else { return nil }
        if let connessione = uscita.connection(with: .video), connessione.isVideoRotationAngleSupported(90) {
            connessione.videoRotationAngle = 90 // app in verticale
        }
        return await withCheckedContinuation { continuazione in
            self.continuazione = continuazione
            uscita.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    fileprivate func consegna(_ immagine: UIImage?) {
        continuazione?.resume(returning: immagine)
        continuazione = nil
    }
}

extension Fotocamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let immagine = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        Task { @MainActor in self.consegna(immagine) }
    }
}

/// Schermata di scatto: anteprima, timer della registrazione in corso, scatti multipli.
struct FotocameraView: View {
    let registratore: Registratore
    /// Immagine e secondo della registrazione in cui è stata scattata.
    let alloScatto: (UIImage, Double) -> Void

    @Environment(\.dismiss) private var chiudi
    @State private var fotocamera = Fotocamera()
    @State private var scatti = 0
    @State private var lampo = false

    static var disponibile: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if fotocamera.negata {
                ContentUnavailableView(
                    "Fotocamera non autorizzata",
                    systemImage: "camera.badge.ellipsis",
                    description: Text("Consenti l'accesso in Impostazioni › Privacy › Fotocamera › Argo.")
                )
            } else {
                AnteprimaFotocamera(sessione: fotocamera.sessione)
                    .ignoresSafeArea()
                    .overlay(Color.white.opacity(lampo ? 0.7 : 0).ignoresSafeArea())
            }

            VStack {
                HStack {
                    // La registrazione continua: lo si vede dal timer.
                    Label(Formato.durata(registratore.durata), systemImage: "record.circle")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(registratore.inPausa ? .yellow : .red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    if scatti > 0 {
                        Text("\(scatti) foto")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()

                Spacer()

                HStack {
                    Button("Fine") { chiudi() }
                        .font(.headline)
                        .buttonStyle(.glass)
                    Spacer()
                    Button {
                        Task { await scatta() }
                    } label: {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(.white.opacity(0.85)).padding(8))
                            .frame(width: 78, height: 78)
                    }
                    .disabled(!fotocamera.pronta)
                    .accessibilityLabel("Scatta")
                    Spacer()
                    // bilancia il pulsante Fine
                    Button("Fine") {}.font(.headline).buttonStyle(.glass).hidden()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .task { await fotocamera.avvia() }
        .onDisappear { fotocamera.ferma() }
    }

    private func scatta() async {
        let secondo = registratore.durata
        withAnimation(.easeOut(duration: 0.15)) { lampo = true }
        let immagine = await fotocamera.scatta()
        withAnimation(.easeIn(duration: 0.2)) { lampo = false }
        if let immagine {
            alloScatto(immagine, secondo)
            scatti += 1
        }
    }
}

private struct AnteprimaFotocamera: UIViewRepresentable {
    let sessione: AVCaptureSession

    func makeUIView(context: Context) -> VistaAnteprima {
        let vista = VistaAnteprima()
        vista.livello.session = sessione
        vista.livello.videoGravity = .resizeAspectFill
        return vista
    }

    func updateUIView(_ uiView: VistaAnteprima, context: Context) {}

    final class VistaAnteprima: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var livello: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
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
