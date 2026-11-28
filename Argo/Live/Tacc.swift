import Foundation
import SwiftData

/// Peppino (nel codice «Tacc»), l'assistente a voce di Taccuino Plus (laboratorio): «Peppino, prendi nota!». Vive dentro Argo Live, anche in CarPlay.
///
/// Il dialogo:
/// 1. «Mi parli di una registrazione?» → sì: Tacc elenca le ultime tre (nome, giorno, ora) e l'utente sceglie per
///    numero o per nome, oppure dice «altre». No: dettatura libera.
/// 2. L'utente detta cosa caricare nel CRM; Tacc risponde breve e chiede i dati che mancano.
/// 3. «Metti in coda» (o «è tutto», o una frase di chiusura): Tacc ricava le azioni con il modello, le legge e
///    chiede conferma. Sì → il dialogo diventa un incontro con le azioni (azioni.json nel pacchetto), che il
///    computer fa confermare prima di scrivere in Dynamics. Il telefono non scrive mai nel CRM.
///
/// Tutto locale: Gemma 4 E2B sul telefono, contesto di 2048 token. Per questo della registrazione scelta va al
/// modello solo il riassunto o, se manca, l'ultimo pezzo di trascrizione.
@MainActor
final class RegiaTacc {
    enum Passo: Equatable { case chiedeRegistrazione, sceltaRegistrazione, dialogo, conferma }

    struct Registrazione {
        let id: UUID
        let titolo: String
        let creata: Date
        let contesto: String
    }

    private(set) var passo: Passo = .chiedeRegistrazione
    private(set) var scelta: Registrazione?
    private var elenco: [Registrazione] = []
    private var pagina = 0
    private(set) var turni: [(chi: String, testo: String)] = []
    private(set) var proposte: [AzioneCRM] = []
    private let inizio = Date()
    let lingua: String

    init(lingua: String) { self.lingua = lingua }

    /// Ci sono parole dell'utente non ancora messe in coda.
    var dialogoAperto: Bool { turni.contains { $0.chi == "io" } && passo != .conferma }

    // MARK: Che cosa risponde Tacc

    enum Mossa {
        case di(String)                     // frase fissa da dire
        case modello(String)                // il testo dell'utente va al modello (dialogo)
        case nuovoDialogo(istruzioni: String, poi: String, domanda: String?)  // apre il dialogo; poi dice la frase o passa la domanda al modello
        case estrai                         // ricava le azioni con il modello
        case salva(String)                  // salva in coda, poi dice la frase
    }

    func benvenuto() -> String {
        caricaElenco()
        return elenco.isEmpty ? frase(.benvenutoSenzaRegistrazioni) : frase(.benvenuto)
    }

    /// Prima mossa se la conversazione parte senza registrazioni sul telefono.
    var partenzaLibera: Bool { elenco.isEmpty }

    func avviaDialogoLibero() -> Mossa {
        passo = .dialogo
        return .nuovoDialogo(istruzioni: istruzioniDialogo(contesto: nil), poi: frase(.cosaMettiamo), domanda: nil)
    }

    func ascolta(_ detto: String) -> Mossa {
        let testo = Self.normalizza(detto)
        switch passo {
        case .chiedeRegistrazione:
            if Self.e(testo, in: Self.si) {
                if elenco.isEmpty { return avviaDialogoLibero() }
                passo = .sceltaRegistrazione
                pagina = 0
                return .di(elencoDaDire())
            }
            if Self.e(testo, in: Self.no) { return avviaDialogoLibero() }
            // Non ha detto né sì né no: forse sta già dettando. Si parte in dettatura libera con quello che ha detto.
            passo = .dialogo
            turni.append(("io", detto))
            return .nuovoDialogo(istruzioni: istruzioniDialogo(contesto: nil), poi: "", domanda: detto)
        case .sceltaRegistrazione:
            if Self.contiene(testo, Self.altre) {
                pagina += 1
                if pagina * 3 >= elenco.count { pagina = 0 }
                return .di(elencoDaDire())
            }
            if Self.e(testo, in: Self.no) { return avviaDialogoLibero() }
            guard let scelta = sceglie(testo) else { return .di(frase(.nonHoCapitoQuale)) }
            self.scelta = scelta
            passo = .dialogo
            return .nuovoDialogo(istruzioni: istruzioniDialogo(contesto: scelta),
                                 poi: frase(.parliamoDi).replacingOccurrences(of: "%@", with: scelta.titolo), domanda: nil)
        case .dialogo:
            if Self.contiene(testo, Self.inCoda) || (SessioneLive.comandoChiusura(detto) && dialogoAperto) {
                return turni.contains(where: { $0.chi == "io" }) ? .estrai : .di(frase(.nienteDaMettere))
            }
            turni.append(("io", detto))
            return .modello(detto)
        case .conferma:
            if Self.e(testo, in: Self.si) || Self.contiene(testo, Self.inCoda) {
                let n = proposte.count
                return .salva(n == 1 ? frase(.messaInCodaUna) : frase(.messeInCoda).replacingOccurrences(of: "%d", with: "\(n)"))
            }
            passo = .dialogo
            proposte = []
            if Self.e(testo, in: Self.no) { return .di(frase(.cosaCambio)) }
            turni.append(("io", detto))
            return .modello(detto)
        }
    }

    /// Il modello ha risposto nel dialogo.
    func risposta(_ testo: String) {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pulito.isEmpty { turni.append(("tacc", pulito)) }
    }

    // MARK: Elenco delle registrazioni

    private func caricaElenco() {
        let contesto = Archivio.contenitore.mainContext
        var richiesta = FetchDescriptor<Sessione>(sortBy: [SortDescriptor(\.creata, order: .reverse)])
        richiesta.fetchLimit = 30
        let sessioni = (try? contesto.fetch(richiesta)) ?? []
        elenco = sessioni.filter { $0.riferimentoTacc == nil && $0.azioniCRM.isEmpty && $0.haTrascrizione }.map {
            Registrazione(id: $0.id, titolo: $0.titolo, creata: $0.creata, contesto: Self.contesto(di: $0))
        }
    }

    /// Cosa sa Tacc della registrazione: riassunto, contatti e punti chiave se c'è la relazione, altrimenti
    /// l'ultimo pezzo della trascrizione. Corto, perché il contesto del modello è di 2048 token.
    static func contesto(di s: Sessione) -> String {
        var parti: [String] = []
        if !s.riassunto.isEmpty { parti.append(s.riassunto) }
        if !s.contatti.isEmpty { parti.append(s.contatti.map(\.descrizione).joined(separator: "; ")) }
        if !s.puntiChiave.isEmpty { parti.append(s.puntiChiave.prefix(6).joined(separator: "; ")) }
        if !s.azioni.isEmpty { parti.append(s.azioni.prefix(5).map(\.testoCompleto).joined(separator: "; ")) }
        var testo = parti.joined(separator: "\n")
        if testo.isEmpty { testo = s.segmenti.isEmpty ? s.trascrizione : s.segmenti.map(\.testo).joined(separator: " ") }
        return testo.count > 1600 ? String(testo.suffix(1600)) : testo
    }

    private func elencoDaDire() -> String {
        let blocco = elenco.dropFirst(pagina * 3).prefix(3)
        let voci = blocco.enumerated().map { indice, r in
            "\(Self.numeri(lingua)[indice]), \(r.titolo), \(Self.quando(r.creata, lingua: lingua))"
        }.joined(separator: "; ")
        return frase(.elenco).replacingOccurrences(of: "%@", with: voci)
    }

    private func sceglie(_ testo: String) -> Registrazione? {
        let blocco = Array(elenco.dropFirst(pagina * 3).prefix(3))
        for (indice, parole) in Self.ordinali.enumerated() where indice < blocco.count {
            if parole.contains(where: { Self.parola(testo, $0) }) { return blocco[indice] }
        }
        // Per nome: la registrazione il cui titolo ha più parole in comune con quello che ha detto
        let dette = Set(testo.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let punteggi = elenco.map { r in (r, Set(Self.normalizza(r.titolo).split(separator: " ").map(String.init)).intersection(dette).count) }
        guard let migliore = punteggi.max(by: { $0.1 < $1.1 }), migliore.1 > 0 else { return nil }
        return migliore.0
    }

    // MARK: Estrazione delle azioni

    /// Testo da dare al modello per ricavare le azioni: data di oggi, registrazione scelta, parole dell'utente.
    func richiestaEstrazione() -> String {
        let oggi = Self.dataISO.string(from: .now)
        var testo = "OGGI: \(oggi)\n"
        if let scelta { testo += "INCONTRO: \(scelta.titolo)\n\(String(scelta.contesto.prefix(900)))\n" }
        let detto = turni.filter { $0.chi == "io" }.map(\.testo).joined(separator: "\n")
        testo += "DETTATO DALL'UTENTE:\n" + String(detto.suffix(2200))
        return testo
    }

    /// Legge la risposta del modello (un array JSON) e prepara le azioni. Ritorna la frase di riepilogo da dire.
    func leggiEstrazione(_ risposta: String) -> String {
        proposte = Self.azioni(da: risposta)
        guard !proposte.isEmpty else {
            passo = .dialogo
            return frase(.nessunaAzione)
        }
        passo = .conferma
        let elenco = proposte.map(\.riepilogo).joined(separator: "; ")
        return frase(.riepilogo).replacingOccurrences(of: "%d", with: "\(proposte.count)")
            .replacingOccurrences(of: "%@", with: elenco)
    }

    static func azioni(da risposta: String) -> [AzioneCRM] {
        guard let a = risposta.firstIndex(of: "["), let b = risposta.lastIndex(of: "]"), a < b,
              let dati = String(risposta[a...b]).data(using: .utf8),
              let grezze = try? JSONSerialization.jsonObject(with: dati) as? [[String: Any]] else { return [] }
        let chiaviDestinatario = ["nome", "cognome", "azienda", "email", "opportunita"]
        let chiaviCampi = ["nome", "cognome", "azienda", "ruolo", "email", "telefono", "cellulare", "argomento",
                           "descrizione", "origine", "valore_stimato", "data_chiusura_stimata", "motivo", "titolo",
                           "testo", "tipo_attivita", "oggetto", "scadenza"]
        return grezze.compactMap { g in
            func valore(_ k: String) -> String {
                if let s = g[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let n = g[k] as? NSNumber { return n.stringValue }
                return ""
            }
            let tipo = valore("tipo")
            guard AzioneCRM.tipi.contains(tipo) else { return nil }
            var riepilogo = valore("riepilogo")
            if riepilogo.isEmpty { riepilogo = tipo }
            var destinatario: [String: String] = [:]
            var campi: [String: String] = [:]
            for k in chiaviDestinatario where !valore(k).isEmpty { destinatario[k] = valore(k) }
            for k in chiaviCampi where !valore(k).isEmpty { campi[k] = valore(k) }
            // Chi crea un lead lo descrive nei campi; chi aggiorna o annota un record lo indica nel destinatario
            if tipo == "lead.crea" { destinatario = [:] }
            for k in ["scadenza", "data_chiusura_stimata"] where campi[k] != nil && dataISO.date(from: campi[k]!) == nil {
                campi[k] = nil  // data non valida: meglio vuota, si mette sul computer
            }
            if let t = campi["tipo_attivita"], t != "telefonata", t != "task" { campi["tipo_attivita"] = "task" }
            if let o = campi["origine"], o != "fiera", o != "altro" { campi["origine"] = nil }
            return AzioneCRM(tipo: tipo, riepilogo: riepilogo, destinatario: destinatario, campi: campi,
                             frase: valore("frase"))
        }
    }

    /// Il dialogo diventa un incontro con le azioni da confermare sul computer.
    func salva() {
        let contesto = Archivio.contenitore.mainContext
        let titolo = scelta.map { frase(.titoloSu).replacingOccurrences(of: "%@", with: $0.titolo) } ?? frase(.titoloLibero)
        let nuova = Sessione(titolo: titolo, lingua: lingua, durata: Date().timeIntervalSince(inizio), nomeFileAudio: nil)
        var secondo = 0.0
        nuova.segmenti = turni.map { t in
            defer { secondo += 1 }
            return Segmento(inizio: secondo, fine: secondo + 1, parlante: t.chi == "io" ? "P1" : "P2", testo: t.testo)
        }
        nuova.nomiParlanti = ["P1": frase(.io), "P2": "Peppino"]
        nuova.trascrizione = turni.map(\.testo).joined(separator: "\n")
        nuova.azioniCRM = proposte
        nuova.riferimentoTacc = scelta?.id
        nuova.stato = .trascritta
        contesto.insert(nuova)
        try? contesto.save()
        turni = []
        proposte = []
        passo = .dialogo
    }

    // MARK: Istruzioni per il modello

    func istruzioniDialogo(contesto: Registrazione?) -> String {
        let base: String
        switch lingua.prefix(2) {
        case "en": base = "You are Peppino, the voice assistant of Argo Notebook. The user is often driving and tells you what to record in the CRM (Dynamics 365 Sales): new or updated leads, opportunities, notes, calls to make, lost deals. Reply in English in one or two short sentences, no lists, no markdown, no emoji. Ask only for missing essentials (company, date of the call back, amount). Never say you have saved anything: when the user is done they say «queue it»."
        case "es": base = "Eres Peppino, el asistente de voz de Argo Cuaderno. El usuario a menudo conduce y te dice qué registrar en el CRM (Dynamics 365 Sales): clientes potenciales nuevos o actualizados, oportunidades, notas, llamadas, oportunidades perdidas. Responde en español con una o dos frases cortas, sin listas, sin markdown, sin emojis. Pide solo lo esencial que falte (empresa, fecha de la llamada, importe). Nunca digas que has guardado algo: cuando termina, el usuario dice «ponlo en cola»."
        case "de": base = "Du bist Peppino, der Sprachassistent von Argo Notizbuch. Der Nutzer fährt oft Auto und sagt dir, was ins CRM (Dynamics 365 Sales) soll: neue oder geänderte Leads, Verkaufschancen, Notizen, Rückrufe, verlorene Geschäfte. Antworte auf Deutsch in ein oder zwei kurzen Sätzen, ohne Listen, ohne Markdown, ohne Emojis. Frage nur nach fehlenden Angaben (Firma, Datum des Rückrufs, Betrag). Sag nie, dass du etwas gespeichert hast: Wenn er fertig ist, sagt der Nutzer «in die Warteschlange»."
        default: base = "Sei Peppino, l'assistente a voce di Argo Taccuino. L'utente spesso guida e ti dice cosa registrare nel CRM (Dynamics 365 Sales): lead nuovi o aggiornati, opportunità, note, telefonate da fare, trattative perse. Rispondi in italiano con una o due frasi brevi, senza elenchi, senza markdown, senza emoji. Chiedi solo i dati essenziali che mancano (azienda, data del richiamo, importo). Non dire mai di aver salvato qualcosa: quando ha finito, l'utente dice «metti in coda»."
        }
        guard let contesto else { return base }
        return base + "\n\n" + frase(.contestoIncontro).replacingOccurrences(of: "%@", with: contesto.titolo) + "\n" + contesto.contesto
    }

    /// Istruzioni dell'estrazione: sempre le stesse (in inglese, il modello le segue meglio), valori nella lingua del dialogo.
    static let istruzioniEstrazione = """
    You turn a salesperson's dictation into CRM actions for Dynamics 365 Sales. Output ONLY a JSON array, no other text.
    Each item has "tipo" (one of: lead.crea, lead.aggiorna, lead.squalifica, contatto.aggiorna, opportunita.crea, opportunita.aggiorna, opportunita.chiudi_persa, nota.crea, attivita.crea), "riepilogo" (one short sentence in the user's language), "frase" (the user's words it comes from) and only the useful keys among:
    nome, cognome, azienda, ruolo, email, telefono, cellulare, argomento, descrizione, origine ("fiera" or "altro"), valore_stimato (number, euro), data_chiusura_stimata (YYYY-MM-DD), motivo, opportunita (topic of an existing opportunity), titolo, testo, tipo_attivita ("telefonata" or "task"), oggetto, scadenza (YYYY-MM-DD).
    Rules: lead.crea for a new person met (nome, cognome, azienda, argomento). For actions on an existing person or company put nome, cognome, azienda to identify them. A call back «in two months» becomes attivita.crea with tipo_attivita "telefonata" and scadenza computed from OGGI. A deal lost or cancelled becomes opportunita.chiudi_persa with motivo. Never invent names, emails, numbers or dates that were not said. If nothing should go to the CRM output [].
    """

    // MARK: Frasi fisse

    enum Frase {
        case benvenuto, benvenutoSenzaRegistrazioni, elenco, nonHoCapitoQuale, parliamoDi, cosaMettiamo, riepilogo
        case nessunaAzione, messeInCoda, messaInCodaUna, cosaCambio, nienteDaMettere, titoloSu, titoloLibero, io
        case contestoIncontro, estraggo
    }

    func frase(_ f: Frase) -> String {
        let tabella: [Frase: [String]] = [  // it, en, es, de
            .benvenuto: ["Ciao, sono Peppino. Mi parli di una registrazione? Dimmi sì o no.",
                         "Hi, I'm Peppino. Is this about a recording? Say yes or no.",
                         "Hola, soy Peppino. ¿Me hablas de una grabación? Di sí o no.",
                         "Hallo, ich bin Peppino. Geht es um eine Aufnahme? Sag ja oder nein."],
            .benvenutoSenzaRegistrazioni: ["Ciao, sono Peppino. Dimmi cosa mettiamo nel CRM.",
                                           "Hi, I'm Peppino. Tell me what goes into the CRM.",
                                           "Hola, soy Peppino. Dime qué ponemos en el CRM.",
                                           "Hallo, ich bin Peppino. Sag mir, was ins CRM soll."],
            .elenco: ["Le ultime: %@. Quale? Dimmi il numero, oppure altre.",
                      "The latest: %@. Which one? Say the number, or more.",
                      "Las últimas: %@. ¿Cuál? Dime el número, o más.",
                      "Die letzten: %@. Welche? Sag die Nummer, oder mehr."],
            .nonHoCapitoQuale: ["Non ho capito quale. Dimmi uno, due o tre, oppure altre.",
                                "I didn't catch which one. Say one, two or three, or more.",
                                "No entendí cuál. Di uno, dos o tres, o más.",
                                "Ich habe nicht verstanden, welche. Sag eins, zwei oder drei, oder mehr."],
            .parliamoDi: ["Va bene, parliamo di %@. Cosa mettiamo nel CRM?",
                          "Okay, let's talk about %@. What goes into the CRM?",
                          "Vale, hablemos de %@. ¿Qué ponemos en el CRM?",
                          "Gut, reden wir über %@. Was soll ins CRM?"],
            .cosaMettiamo: ["Ti ascolto: cosa mettiamo nel CRM? Quando hai finito di' metti in coda.",
                            "I'm listening: what goes into the CRM? When you're done say queue it.",
                            "Te escucho: ¿qué ponemos en el CRM? Cuando termines di ponlo en cola.",
                            "Ich höre zu: Was soll ins CRM? Wenn du fertig bist, sag in die Warteschlange."],
            .riepilogo: ["Ho capito %d azioni: %@. Le metto in coda? Dimmi sì o no.",
                         "I got %d actions: %@. Shall I queue them? Say yes or no.",
                         "He entendido %d acciones: %@. ¿Las pongo en cola? Di sí o no.",
                         "Ich habe %d Aktionen verstanden: %@. Soll ich sie einreihen? Sag ja oder nein."],
            .nessunaAzione: ["Non ho trovato niente da mettere nel CRM. Dimmelo in un altro modo?",
                             "I found nothing for the CRM. Can you put it another way?",
                             "No encontré nada para el CRM. ¿Me lo dices de otra forma?",
                             "Ich habe nichts fürs CRM gefunden. Sagst du es anders?"],
            .messeInCoda: ["Fatto: %d azioni in coda. Le confermi sul computer. Vuoi aggiungere altro?",
                           "Done: %d actions queued. You confirm them on the computer. Anything else?",
                           "Hecho: %d acciones en cola. Las confirmas en el ordenador. ¿Algo más?",
                           "Erledigt: %d Aktionen eingereiht. Du bestätigst sie am Computer. Noch etwas?"],
            .messaInCodaUna: ["Fatto: un'azione in coda. La confermi sul computer. Vuoi aggiungere altro?",
                              "Done: one action queued. You confirm it on the computer. Anything else?",
                              "Hecho: una acción en cola. La confirmas en el ordenador. ¿Algo más?",
                              "Erledigt: eine Aktion eingereiht. Du bestätigst sie am Computer. Noch etwas?"],
            .cosaCambio: ["Va bene, non metto niente in coda. Cosa cambio?",
                          "Okay, nothing queued. What should I change?",
                          "Vale, no pongo nada en cola. ¿Qué cambio?",
                          "Gut, nichts eingereiht. Was soll ich ändern?"],
            .nienteDaMettere: ["Non mi hai ancora detto niente da mettere nel CRM.",
                               "You haven't told me anything for the CRM yet.",
                               "Todavía no me has dicho nada para el CRM.",
                               "Du hast mir noch nichts fürs CRM gesagt."],
            .titoloSu: ["Peppino · %@", "Peppino · %@", "Peppino · %@", "Peppino · %@"],
            .titoloLibero: ["Peppino · dettatura", "Peppino · dictation", "Peppino · dictado", "Peppino · Diktat"],
            .io: ["Io", "Me", "Yo", "Ich"],
            .contestoIncontro: ["L'utente parla di questo incontro registrato, «%@»:",
                                "The user is talking about this recorded meeting, «%@»:",
                                "El usuario habla de esta reunión grabada, «%@»:",
                                "Der Nutzer spricht über diesen aufgenommenen Termin, «%@»:"],
            .estraggo: ["Un attimo, preparo le azioni.", "One moment, preparing the actions.",
                        "Un momento, preparo las acciones.", "Einen Moment, ich bereite die Aktionen vor."],
        ]
        let indice = ["it": 0, "en": 1, "es": 2, "de": 3][String(lingua.prefix(2))] ?? 0
        return tabella[f]?[indice] ?? ""
    }

    // MARK: Parole

    static let si: Set<String> = ["si", "sì", "certo", "ok", "okay", "va bene", "esatto", "volentieri", "yes", "yeah",
                                  "yep", "sure", "sí", "claro", "vale", "ja", "genau", "klar", "gerne", "conferma",
                                  "confermo", "procedi", "sì grazie", "si grazie"]
    static let no: Set<String> = ["no", "no grazie", "nope", "nein", "nein danke", "no gracias", "niente", "nessuna"]
    static let altre = ["altre", "altri", "altro", "more", "others", "más", "otras", "mehr", "andere", "weitere"]
    static let inCoda = ["metti in coda", "mettile in coda", "mettilo in coda", "in coda", "è tutto", "ho finito",
                         "queue it", "queue them", "that's it", "i'm done", "ponlo en cola", "en cola", "es todo",
                         "he terminado", "in die warteschlange", "einreihen", "das ist alles", "fertig"]
    static let ordinali: [[String]] = [
        ["1", "uno", "una", "primo", "prima", "one", "first", "primera", "primero", "eins", "erste", "ersten"],
        ["2", "due", "secondo", "seconda", "two", "second", "dos", "segunda", "segundo", "zwei", "zweite", "zweiten"],
        ["3", "tre", "terzo", "terza", "three", "third", "tres", "tercera", "tercero", "drei", "dritte", "dritten"],
    ]

    static func numeri(_ lingua: String) -> [String] {
        switch lingua.prefix(2) {
        case "en": ["one", "two", "three"]
        case "es": ["uno", "dos", "tres"]
        case "de": ["eins", "zwei", "drei"]
        default: ["uno", "due", "tre"]
        }
    }

    static let dataISO: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func quando(_ data: Date, lingua: String) -> String {
        let locale = Locale(identifier: lingua)
        let ora = data.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        if Calendar.current.isDateInToday(data) { return ["it": "oggi alle", "en": "today at", "es": "hoy a las", "de": "heute um"][String(lingua.prefix(2))].map { "\($0) \(ora)" } ?? ora }
        if Calendar.current.isDateInYesterday(data) { return ["it": "ieri alle", "en": "yesterday at", "es": "ayer a las", "de": "gestern um"][String(lingua.prefix(2))].map { "\($0) \(ora)" } ?? ora }
        return data.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    /// Minuscole, senza punteggiatura (tranne l'apostrofo), spazi singoli.
    static func normalizza(_ testo: String) -> String {
        testo.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'")))
            .joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// La frase intera è una delle risposte (sì/no), al massimo con qualche parola in più all'inizio o in fondo.
    static func e(_ testo: String, in insieme: Set<String>) -> Bool {
        if insieme.contains(testo) { return true }
        let parole = testo.split(separator: " ").map(String.init)
        guard parole.count <= 4 else { return false }
        return parole.contains { insieme.contains($0) } && !parole.contains { (insieme == si ? no : si).contains($0) }
    }

    static func contiene(_ testo: String, _ frasi: [String]) -> Bool {
        frasi.contains { parola(testo, $0) }
    }

    static func parola(_ testo: String, _ cercata: String) -> Bool {
        " \(testo) ".contains(" \(cercata) ")
    }
}
