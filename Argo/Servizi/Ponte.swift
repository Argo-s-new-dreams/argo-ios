import Foundation
import CryptoKit
import Network
import Security
import SwiftData
import UIKit

/// Ponte Argo: canale cifrato con Argo desktop in rete locale (vedi argo-ai/app/ponte.py).
/// - Abbinamento: QR mostrato da Argo desktop con indirizzi, porta, impronta del certificato e codice monouso.
/// - Ogni connessione è HTTPS e accetta solo il certificato con quell'impronta (pinning): niente cloud,
///   niente autorità esterne, niente «fidati di tutto».
/// - Il segreto ricevuto all'abbinamento sta nel Portachiavi, solo su questo iPhone.
/// - Su un'altra rete gli indirizzi cambiano: se quelli salvati non rispondono, l'iPhone cerca il computer con
///   Bonjour (servizio «_argoponte._tcp») per id, e ogni /v1/stato aggiorna indirizzi e porta. L'identità del
///   computer resta l'impronta del certificato, non l'indirizzo.
struct AbbinamentoPonte: Codable, Equatable {
    var nome: String
    var porta: Int
    var indirizzi: [String]
    /// SHA-256 del certificato del computer, base64url.
    var impronta: String
    var collegato: Date
    var ultimaSincronizzazione: Date?
    /// Id del computer (Argo desktop dalla 20261125): serve a ritrovarlo con Bonjour. nil negli abbinamenti di prima.
    var id: String? = nil
}

enum ErrorePonte: LocalizedError {
    case qrNonValido, nonCollegato, irraggiungibile, rifiutato(String), risposta

    var errorDescription: String? {
        switch self {
        case .qrNonValido: String(localized: "Questo non è il QR di Argo: su computer apri Incontri › Collega iPhone.")
        case .nonCollegato: String(localized: "Nessun computer collegato.")
        case .irraggiungibile: String(localized: "Non raggiungo Argo sul computer: deve essere aperto e sulla stessa rete.")
        case .rifiutato(let motivo): motivo
        case .risposta: String(localized: "Risposta inattesa da Argo sul computer.")
        }
    }
}

@MainActor
enum Ponte {

    // MARK: Abbinamento

    private struct ContenutoQR: Decodable {
        let v: Int
        let n: String
        let p: Int
        let h: [String]
        let f: String
        let c: String
        let i: String?
    }

    static var abbinamento: AbbinamentoPonte? {
        get {
            guard let dati = UserDefaults.standard.data(forKey: "ponte") else { return nil }
            return try? JSONDecoder().decode(AbbinamentoPonte.self, from: dati)
        }
        set {
            if let newValue, let dati = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(dati, forKey: "ponte")
            } else {
                UserDefaults.standard.removeObject(forKey: "ponte")
            }
        }
    }

    static func abbina(qr testo: String) async throws -> AbbinamentoPonte {
        guard testo.hasPrefix("argo-ponte:"),
              let dati = testo.dropFirst("argo-ponte:".count).data(using: .utf8),
              let qr = try? JSONDecoder().decode(ContenutoQR.self, from: dati), qr.v == 1
        else { throw ErrorePonte.qrNonValido }

        var nuovo = AbbinamentoPonte(nome: qr.n, porta: qr.p, indirizzi: qr.h, impronta: qr.f, collegato: .now, id: qr.i)
        let corpo = try JSONEncoder().encode(["codice": qr.c, "nome": UIDevice.current.name])
        let (risposta, indirizzo) = try await richiesta(
            "POST", "/v1/abbina", corpo: corpo, tipo: "application/json", segreto: nil, verso: nuovo, attesa: 10)

        struct Esito: Decodable { let segreto: String; let nome: String }
        guard let esito = try? JSONDecoder().decode(Esito.self, from: risposta) else { throw ErrorePonte.risposta }
        Portachiavi.salva(esito.segreto)
        nuovo.nome = esito.nome
        nuovo.indirizzi = [indirizzo] + qr.h.filter { $0 != indirizzo }
        abbinamento = nuovo
        return nuovo
    }

    static func scollega() {
        abbinamento = nil
        Portachiavi.elimina()
    }

    // MARK: Servizi

    /// Scarica l'anagrafe voci scelta sul computer (Voci › Per iPhone). nil se non ne è stata scelta nessuna.
    /// Se sul computer il riconoscimento delle voci è spento (Argo desktop dalla 20261119.1720), elimina
    /// l'anagrafe già scaricata: l'iPhone smette di riconoscere le persone, come il computer.
    static func scaricaAnagrafe() async throws -> AnagrafeVoci? {
        do {
            let (dati, _) = try await richiestaAutenticata("GET", "/v1/anagrafe", attesa: 20)
            return try ArchivioAnagrafe.importa(dati: dati)
        } catch ErrorePonte.rifiutato(let motivo) where motivo.contains("Riconoscimento delle voci spento") {
            ArchivioAnagrafe.elimina()
            return nil
        } catch ErrorePonte.rifiutato(let motivo) where motivo.contains("Nessuna voce") {
            return nil
        }
    }

    static func invia(_ sessione: Sessione) async throws {
        let pacchetto = try Esportatore.pacchetto(di: sessione)
        defer { try? FileManager.default.removeItem(at: pacchetto) }
        let dati = try Data(contentsOf: pacchetto)
        _ = try await richiestaAutenticata("POST", "/v1/incontri", corpo: dati, tipo: "application/zip", attesa: 300)
        sessione.inviataAdArgo = .now
    }

    /// Sincronizzazione completa: anagrafe giù, incontri pronti su. Silenziosa se il computer non c'è.
    @discardableResult
    static func sincronizza(_ contesto: ModelContext) async -> String? {
        guard abbinamento != nil else { return nil }
        var fatto: [String] = []
        do {
            // Prima un controllo veloce (pochi secondi): se il computer non c'è, si rinuncia subito.
            _ = try await richiestaAutenticata("GET", "/v1/stato", attesa: 4)
            if let anagrafe = try await scaricaAnagrafe() {
                fatto.append(String(localized: "\(anagrafe.voci.count) voci aggiornate"))
            }
            let pronte = try contesto.fetch(FetchDescriptor<Sessione>()).filter {
                $0.inviataAdArgo == nil && !Elaborazione.inCorso.contains($0.id)
                    && ($0.stato == .trascritta || $0.stato == .completata)
            }
            let elimina = UserDefaults.standard.bool(forKey: "eliminaDopoInvio")
            for sessione in pronte {
                try await invia(sessione)
                if elimina {
                    sessione.eliminaFile()
                    contesto.delete(sessione)
                }
            }
            if !pronte.isEmpty {
                fatto.append(pronte.count == 1 ? String(localized: "1 incontro inviato") : String(localized: "\(pronte.count) incontri inviati"))
            }
            abbinamento?.ultimaSincronizzazione = .now
            return fatto.isEmpty ? nil : String(localized: "Argo sul computer: \(fatto.joined(separator: ", "))")
        } catch ErrorePonte.irraggiungibile {
            return nil // fuori casa o computer spento: si riprova alla prossima occasione
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Rete

    private static func richiestaAutenticata(
        _ metodo: String, _ percorso: String, corpo: Data? = nil, tipo: String? = nil, attesa: TimeInterval
    ) async throws -> (Data, String) {
        guard var abbinamento, let segreto = Portachiavi.leggi() else { throw ErrorePonte.nonCollegato }
        let esito: (Data, String)
        do {
            esito = try await richiesta(metodo, percorso, corpo: corpo, tipo: tipo, segreto: segreto,
                                        verso: abbinamento, attesa: attesa)
        } catch ErrorePonte.irraggiungibile {
            // Altra rete o altra porta: si cerca il computer con Bonjour e si riprova una volta.
            guard let (host, porta) = await ScopertaPonte.trova(id: abbinamento.id, nome: abbinamento.nome)
            else { throw ErrorePonte.irraggiungibile }
            abbinamento.porta = porta
            abbinamento.indirizzi = [host] + abbinamento.indirizzi.filter { $0 != host }
            self.abbinamento = abbinamento
            esito = try await richiesta(metodo, percorso, corpo: corpo, tipo: tipo, segreto: segreto,
                                        verso: abbinamento, attesa: attesa)
        }
        // L'indirizzo che ha risposto va in cima: la prossima volta si prova per primo.
        var aggiornato = abbinamento
        aggiornato.indirizzi = [esito.1] + abbinamento.indirizzi.filter { $0 != esito.1 }
        // /v1/stato (Argo desktop dalla 20261125) porta gli indirizzi e la porta di adesso, e l'id del computer.
        if percorso == "/v1/stato" {
            struct Stato: Decodable { let id: String?; let h: [String]?; let p: Int? }
            if let stato = try? JSONDecoder().decode(Stato.self, from: esito.0) {
                if let h = stato.h, !h.isEmpty {
                    let nuovi = h.filter { $0 != esito.1 }
                    aggiornato.indirizzi = Array(([esito.1] + nuovi + aggiornato.indirizzi.filter { !nuovi.contains($0) && $0 != esito.1 }).prefix(6))
                }
                if let p = stato.p, p > 0 { aggiornato.porta = p }
                if aggiornato.id == nil, let id = stato.id { aggiornato.id = id }
            }
        }
        if aggiornato != abbinamento { self.abbinamento = aggiornato }
        return esito
    }

    /// Prova gli indirizzi del computer in ordine; restituisce corpo della risposta e indirizzo che ha risposto.
    private static func richiesta(
        _ metodo: String, _ percorso: String, corpo: Data?, tipo: String?, segreto: String?,
        verso destinazione: AbbinamentoPonte, attesa: TimeInterval
    ) async throws -> (Data, String) {
        let sessione = URLSession(configuration: .ephemeral, delegate: PinningPonte(destinazione.impronta), delegateQueue: nil)
        defer { sessione.finishTasksAndInvalidate() }

        for indirizzo in destinazione.indirizzi {
            let host = indirizzo.contains(":") ? "[\(indirizzo)]" : indirizzo
            guard let url = URL(string: "https://\(host):\(destinazione.porta)\(percorso)") else { continue }
            var r = URLRequest(url: url)
            r.httpMethod = metodo
            // Il primo tentativo è breve: se l'indirizzo non risponde si passa al successivo.
            r.timeoutInterval = metodo == "GET" && percorso == "/v1/stato" ? 4 : attesa
            if let tipo { r.setValue(tipo, forHTTPHeaderField: "Content-Type") }
            if let segreto { r.setValue("Bearer \(segreto)", forHTTPHeaderField: "Authorization") }
            do {
                let dati: Data
                let risposta: URLResponse
                if let corpo {
                    (dati, risposta) = try await sessione.upload(for: r, from: corpo)
                } else {
                    (dati, risposta) = try await sessione.data(for: r)
                }
                guard let http = risposta as? HTTPURLResponse else { continue }
                guard (200..<300).contains(http.statusCode) else {
                    struct Errore: Decodable { let errore: String }
                    let motivo = (try? JSONDecoder().decode(Errore.self, from: dati))?.errore
                    throw ErrorePonte.rifiutato(motivo ?? String(localized: "Argo sul computer ha risposto con errore \(http.statusCode)."))
                }
                return (dati, indirizzo)
            } catch is URLError {
                // Indirizzo non raggiungibile, oppure certificato diverso dall'atteso (non è il tuo Argo):
                // si prova il prossimo indirizzo.
                continue
            }
        }
        throw ErrorePonte.irraggiungibile
    }
}

/// Ritrova Argo sul computer in rete locale con Bonjour, per id (o per nome negli abbinamenti di prima).
/// Restituisce indirizzo e porta di adesso; il canale resta protetto da impronta del certificato e segreto.
enum ScopertaPonte {
    static let servizio = "_argoponte._tcp"

    static func trova(id: String?, nome: String, attesa: TimeInterval = 5) async -> (String, Int)? {
        guard let endpoint = await cerca(id: id, nome: nome, attesa: attesa) else { return nil }
        return await risolvi(endpoint, attesa: attesa)
    }

    /// Una sola risposta per ricerca, anche se gli eventi arrivano più volte.
    private final class UnaVolta<T>: @unchecked Sendable {
        private let blocco = NSLock()
        private var continuazione: CheckedContinuation<T, Never>?
        init(_ c: CheckedContinuation<T, Never>) { continuazione = c }
        func fine(_ valore: T) {
            blocco.lock()
            let c = continuazione
            continuazione = nil
            blocco.unlock()
            c?.resume(returning: valore)
        }
    }

    private static func cerca(id: String?, nome: String, attesa: TimeInterval) async -> NWEndpoint? {
        await withCheckedContinuation { (c: CheckedContinuation<NWEndpoint?, Never>) in
            let esito = UnaVolta(c)
            let coda = DispatchQueue(label: "argo.ponte.scoperta")
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: servizio, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { risultati, _ in
                for r in risultati {
                    if let id, case let .bonjour(txt) = r.metadata, txt["id"] == id {
                        browser.cancel(); esito.fine(r.endpoint); return
                    }
                    if id == nil, case let .service(nomeServizio, _, _, _) = r.endpoint, nomeServizio == "Argo \(nome)" {
                        browser.cancel(); esito.fine(r.endpoint); return
                    }
                }
            }
            browser.stateUpdateHandler = { stato in
                if case .failed = stato { browser.cancel(); esito.fine(nil) }
            }
            browser.start(queue: coda)
            coda.asyncAfter(deadline: .now() + attesa) { browser.cancel(); esito.fine(nil) }
        }
    }

    private static func risolvi(_ endpoint: NWEndpoint, attesa: TimeInterval) async -> (String, Int)? {
        await withCheckedContinuation { (c: CheckedContinuation<(String, Int)?, Never>) in
            let esito = UnaVolta(c)
            let coda = DispatchQueue(label: "argo.ponte.risolvi")
            let parametri = NWParameters.tcp
            let connessione = NWConnection(to: endpoint, using: parametri)
            connessione.stateUpdateHandler = { stato in
                switch stato {
                case .ready:
                    var trovato: (String, Int)?
                    if case let .hostPort(host, porta)? = connessione.currentPath?.remoteEndpoint {
                        switch host {
                        case .ipv4(let indirizzo):
                            trovato = ("\(indirizzo)", Int(porta.rawValue))
                        case .ipv6(let indirizzo):
                            // Nell'URL il «%» dell'interfaccia va scritto «%25»
                            trovato = ("\(indirizzo)".replacingOccurrences(of: "%", with: "%25"), Int(porta.rawValue))
                        case .name(let nomeHost, _):
                            trovato = (nomeHost, Int(porta.rawValue))
                        @unknown default:
                            trovato = nil
                        }
                    }
                    connessione.cancel()
                    esito.fine(trovato)
                case .failed, .cancelled:
                    esito.fine(nil)
                default:
                    break
                }
            }
            connessione.start(queue: coda)
            coda.asyncAfter(deadline: .now() + attesa) { connessione.cancel(); esito.fine(nil) }
        }
    }
}

/// Accetta solo il certificato con l'impronta ricevuta dal QR.
final class PinningPonte: NSObject, URLSessionDelegate {
    let impronta: String
    init(_ impronta: String) { self.impronta = impronta }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let fiducia = challenge.protectionSpace.serverTrust,
              let catena = SecTrustCopyCertificateChain(fiducia) as? [SecCertificate],
              let foglia = catena.first
        else { return (.cancelAuthenticationChallenge, nil) }
        let digest = SHA256.hash(data: SecCertificateCopyData(foglia) as Data)
        let base64url = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard base64url == impronta else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: fiducia))
    }
}

/// Segreto del Ponte nel Portachiavi: solo su questo iPhone, disponibile dopo il primo sblocco.
enum Portachiavi {
    private static let servizio = "blog.argosnewdreams.argo.ponte"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servizio,
         kSecAttrAccount as String: "segreto"]
    }

    static func salva(_ segreto: String) {
        elimina()
        var voce = base
        voce[kSecValueData as String] = Data(segreto.utf8)
        voce[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(voce as CFDictionary, nil)
    }

    static func leggi() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var risultato: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &risultato) == errSecSuccess,
              let dati = risultato as? Data else { return nil }
        return String(data: dati, encoding: .utf8)
    }

    static func elimina() {
        SecItemDelete(base as CFDictionary)
    }
}
