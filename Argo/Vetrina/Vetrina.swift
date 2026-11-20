#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Modalità vetrina: dati di prova per gli screenshot dell'App Store.
/// Esiste solo nelle build Debug e si attiva con l'argomento di avvio `-ArgoVetrina <schermata>`
/// (vedi `strumenti/screenshot-appstore.sh`). Non tocca l'archivio vero: usa un contenitore in memoria.
/// Persone, aziende e recapiti sono inventati.
@MainActor
enum Vetrina {
    enum Schermata: String, CaseIterable {
        case elenco, informativa, registrazione, relazione, trascrizione, foto
    }

    static let schermata: Schermata? = {
        let argomenti = ProcessInfo.processInfo.arguments
        guard let indice = argomenti.firstIndex(of: "-ArgoVetrina"), indice + 1 < argomenti.count else { return nil }
        return Schermata(rawValue: argomenti[indice + 1])
    }()

    static var attiva: Bool { schermata != nil }

    /// Le schermate che partono già dentro l'incontro principale.
    static var apreIncontro: Bool {
        guard let schermata else { return false }
        return [.relazione, .trascrizione, .foto].contains(schermata)
    }

    static let contenitore: ModelContainer = {
        let configurazione = ModelConfiguration(isStoredInMemoryOnly: true)
        let contenitore = try! ModelContainer(for: Sessione.self, configurations: configurazione)
        popola(contenitore.mainContext)
        return contenitore
    }()

    /// Le due foto scattate durante la registrazione di prova.
    static var fotoRegistrazione: [FotoSessione] { [biglietto, scheda] }

    // MARK: Foto di prova (disegnate qui, nessuna immagine reale)

    static let biglietto: FotoSessione = FotoSessione(
        nomeFile: salva(disegnaBiglietto(), nome: "vetrina-biglietto.jpg"),
        secondo: 95,
        testoOCR: "OFFICINE VALMAIRA S.R.L.\nGiulia Ferrero\nResponsabile acquisti\ngiulia.ferrero@valmaira.example\n+39 0171 000 0000\nwww.valmaira.example",
        riferimenti: ["giulia.ferrero@valmaira.example", "+39 0171 000 0000", "http://www.valmaira.example"],
        letta: true
    )

    static let scheda: FotoSessione = FotoSessione(
        nomeFile: salva(disegnaScheda(), nome: "vetrina-scheda.jpg"),
        secondo: 612,
        testoOCR: "LINEA L3 · CONFEZIONATRICE VERTICALE\nSensori: vibrazione (4), temperatura (6), corrente motori\nFermi non programmati 2026: 37 ore\nManutenzione: trimestrale",
        riferimenti: [],
        letta: true
    )

    private static func salva(_ immagine: UIImage, nome: String) -> String {
        let url = Archivio.cartellaFoto.appending(path: nome)
        if let dati = immagine.jpegData(compressionQuality: 0.9) { try? dati.write(to: url) }
        return nome
    }

    private static let terracotta = UIColor(red: 0.851, green: 0.482, blue: 0.369, alpha: 1)

    private static func testo(_ stringa: String, _ dimensione: CGFloat, _ peso: UIFont.Weight,
                              _ colore: UIColor, at punto: CGPoint) {
        let attributi: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: dimensione, weight: peso),
            .foregroundColor: colore,
        ]
        (stringa as NSString).draw(at: punto, withAttributes: attributi)
    }

    private static func disegnaBiglietto() -> UIImage {
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        let dimensione = CGSize(width: 1400, height: 1000)
        return UIGraphicsImageRenderer(size: dimensione, format: formato).image { contesto in
            // il tavolo dello stand
            UIColor(red: 0.30, green: 0.24, blue: 0.20, alpha: 1).setFill()
            contesto.fill(CGRect(origin: .zero, size: dimensione))
            // il biglietto
            let carta = CGRect(x: 170, y: 200, width: 1060, height: 600)
            UIColor(white: 0, alpha: 0.35).setFill()
            UIBezierPath(roundedRect: carta.offsetBy(dx: 14, dy: 18), cornerRadius: 18).fill()
            UIColor(white: 0.98, alpha: 1).setFill()
            UIBezierPath(roundedRect: carta, cornerRadius: 18).fill()
            terracotta.setFill()
            contesto.fill(CGRect(x: carta.minX, y: carta.minY + 70, width: 18, height: 140))
            let nero = UIColor(white: 0.12, alpha: 1)
            let grigio = UIColor(white: 0.40, alpha: 1)
            testo("OFFICINE VALMAIRA S.R.L.", 34, .heavy, terracotta, at: CGPoint(x: 240, y: 270))
            testo("Giulia Ferrero", 64, .semibold, nero, at: CGPoint(x: 240, y: 330))
            testo("Responsabile acquisti", 36, .regular, grigio, at: CGPoint(x: 240, y: 415))
            testo("giulia.ferrero@valmaira.example", 34, .regular, nero, at: CGPoint(x: 240, y: 590))
            testo("+39 0171 000 0000", 34, .regular, nero, at: CGPoint(x: 240, y: 640))
            testo("www.valmaira.example", 34, .regular, nero, at: CGPoint(x: 240, y: 690))
        }
    }

    private static func disegnaScheda() -> UIImage {
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        let dimensione = CGSize(width: 1000, height: 1400)
        return UIGraphicsImageRenderer(size: dimensione, format: formato).image { contesto in
            UIColor(red: 0.25, green: 0.27, blue: 0.30, alpha: 1).setFill()
            contesto.fill(CGRect(origin: .zero, size: dimensione))
            let foglio = CGRect(x: 90, y: 80, width: 820, height: 1240)
            UIColor(white: 0.97, alpha: 1).setFill()
            contesto.fill(foglio)
            let nero = UIColor(white: 0.12, alpha: 1)
            let grigio = UIColor(white: 0.45, alpha: 1)
            testo("SCHEDA TECNICA", 26, .bold, terracotta, at: CGPoint(x: 150, y: 150))
            testo("Linea L3", 60, .bold, nero, at: CGPoint(x: 150, y: 190))
            testo("Confezionatrice verticale", 34, .regular, grigio, at: CGPoint(x: 150, y: 270))
            let righe = [
                ("Sensori di vibrazione", "4"),
                ("Sensori di temperatura", "6"),
                ("Corrente motori", "sì"),
                ("Manutenzione", "trimestrale"),
                ("Fermi non programmati 2026", "37 ore"),
            ]
            for (indice, riga) in righe.enumerated() {
                let y = CGFloat(400 + indice * 90)
                UIColor(white: 0.85, alpha: 1).setFill()
                contesto.fill(CGRect(x: 150, y: y + 70, width: 700, height: 2))
                testo(riga.0, 32, .regular, nero, at: CGPoint(x: 150, y: y + 18))
                testo(riga.1, 32, .semibold, nero, at: CGPoint(x: 680, y: y + 18))
            }
            // un grafico a barre stilizzato
            let valori: [CGFloat] = [0.35, 0.55, 0.42, 0.80, 0.62, 0.95]
            for (indice, valore) in valori.enumerated() {
                let altezza = 220 * valore
                let colore = indice == valori.count - 1 ? terracotta : UIColor(white: 0.70, alpha: 1)
                colore.setFill()
                contesto.fill(CGRect(x: 170 + CGFloat(indice) * 110, y: 1220 - altezza, width: 70, height: altezza))
            }
        }
    }

    // MARK: Incontri di prova

    private static func popola(_ contesto: ModelContext) {
        let adesso = Date.now

        // 1 · l'incontro principale: fiera, tre voci, due foto, relazione completa
        let fiera = Sessione(titolo: "Officine Valmaira · stand B12", lingua: "it-IT", durata: 1123,
                             nomeFileAudio: nil, foto: [biglietto, scheda])
        fiera.creata = adesso.addingTimeInterval(-55 * 60)
        fiera.stato = .completata
        fiera.nomiParlanti = ["P1": "Io", "P2": "Giulia Ferrero", "P3": "Marco Bianco"]
        fiera.segmenti = [
            Segmento(inizio: 4, fine: 11, parlante: "P2", testo: "Buongiorno! Sì, siamo noi Officine Valmaira: facciamo linee di confezionamento per l'alimentare."),
            Segmento(inizio: 12, fine: 19, parlante: "P1", testo: "Piacere. Mi interessava capire come gestite oggi i fermi macchina."),
            Segmento(inizio: 20, fine: 31, parlante: "P2", testo: "A calendario: una manutenzione ogni tre mesi. Ma i fermi non programmati ci costano parecchio."),
            Segmento(inizio: 33, fine: 44, parlante: "P3", testo: "Sulla linea L3 i sensori di vibrazione ci sono già, però i dati restano lì: nessuno li guarda davvero."),
            Segmento(inizio: 46, fine: 58, parlante: "P1", testo: "È proprio il punto: con quei dati si può capire quando un cuscinetto sta per cedere e intervenire prima."),
            Segmento(inizio: 60, fine: 68, parlante: "P2", testo: "E i dati dove finiscono? Per noi è delicato, i clienti ci chiedono garanzie."),
            Segmento(inizio: 69, fine: 80, parlante: "P1", testo: "Restano in azienda, nel vostro ambiente: niente servizi esterni, decidete voi cosa condividere."),
            Segmento(inizio: 97, fine: 104, parlante: "P2", testo: "Le lascio il mio biglietto, così ci sentiamo dopo la fiera."),
            Segmento(inizio: 598, fine: 610, parlante: "P3", testo: "Le faccio vedere la scheda della L3: qui ci sono i sensori e le ore di fermo di quest'anno."),
            Segmento(inizio: 1080, fine: 1092, parlante: "P2", testo: "Ci vediamo a gennaio in stabilimento? Porto anche il responsabile di produzione."),
            Segmento(inizio: 1094, fine: 1104, parlante: "P1", testo: "Perfetto: preparo una proposta per un pilota di otto settimane sulla L3."),
        ]
        fiera.trascrizione = fiera.segmenti.map(\.testo).joined(separator: " ")
        fiera.riassunto = "Primo contatto allo stand con Officine Valmaira, che costruisce linee di confezionamento per l'alimentare. Oggi la manutenzione è a calendario e i fermi non programmati pesano sui costi; sulla linea L3 i sensori ci sono già, ma i dati non vengono usati. C'è interesse per un pilota di manutenzione predittiva, a patto che i dati restino in azienda."
        fiera.contatti = [
            Contatto(nome: "Giulia Ferrero", azienda: "Officine Valmaira S.r.l.", ruolo: "Responsabile acquisti",
                     email: "giulia.ferrero@valmaira.example", telefono: "+39 0171 000 0000"),
            Contatto(nome: "Marco Bianco", azienda: "Officine Valmaira S.r.l.", ruolo: "Responsabile manutenzione"),
        ]
        fiera.puntiChiave = [
            "Manutenzione oggi solo a calendario, ogni tre mesi",
            "37 ore di fermi non programmati nel 2026 sulla linea L3",
            "Sensori di vibrazione e temperatura già installati",
            "Requisito: i dati restano in azienda",
        ]
        fiera.azioni = [
            Azione(descrizione: "Preparare la proposta per un pilota di 8 settimane sulla L3", responsabile: "Io", scadenza: "12 dicembre"),
            Azione(descrizione: "Inviare la scheda tecnica completa della L3", responsabile: "Marco Bianco", scadenza: "fine settimana"),
            Azione(descrizione: "Fissare la visita in stabilimento", responsabile: "Giulia Ferrero", scadenza: "gennaio"),
        ]
        fiera.motoreVerbale = "Apple Intelligence"
        fiera.inviataAdArgo = adesso.addingTimeInterval(-20 * 60)
        contesto.insert(fiera)

        // 2–4 · altri incontri, per dare vita all'elenco
        let altri: [(String, TimeInterval, TimeInterval, Int, [FotoSessione])] = [
            ("Caffè con Studio Lanteri", -26 * 3600, 1520, 2, []),
            ("Demo linea L3 · Termoplast", -50 * 3600, 2710, 4, [scheda]),
            ("Avanzamento progetto Fiera 2027", -6 * 24 * 3600, 3305, 3, []),
        ]
        for (titolo, quando, durata, voci, foto) in altri {
            let incontro = Sessione(titolo: titolo, lingua: "it-IT", durata: durata, nomeFileAudio: nil, foto: foto)
            incontro.creata = adesso.addingTimeInterval(quando)
            incontro.stato = .completata
            incontro.segmenti = (1...voci).map { numero in
                Segmento(inizio: Double(numero * 10), fine: Double(numero * 10 + 8), parlante: "P\(numero)", testo: "…")
            }
            incontro.trascrizione = "…"
            incontro.riassunto = "Incontro di prova."
            incontro.motoreVerbale = "Apple Intelligence"
            incontro.inviataAdArgo = incontro.creata.addingTimeInterval(3600)
            contesto.insert(incontro)
        }
        try? contesto.save()
    }
}

/// La schermata di partenza in modalità vetrina.
struct VetrinaView: View {
    let schermata: Vetrina.Schermata

    var body: some View {
        Group {
            switch schermata {
            case .informativa, .registrazione:
                RegistraView { _, _, _ in }
            case .elenco, .relazione, .trascrizione, .foto:
                ElencoSessioniView()
            }
        }
        .preferredColorScheme(.dark)
        .modelContainer(Vetrina.contenitore)
    }
}
#endif
