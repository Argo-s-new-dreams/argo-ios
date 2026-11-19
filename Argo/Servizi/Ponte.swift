import Foundation
import CryptoKit
import Security
import SwiftData
import UIKit

/// Ponte Argo: canale cifrato con Argo desktop in rete locale (vedi argo-ai/app/ponte.py).
/// - Abbinamento: QR mostrato da Argo desktop con indirizzi, porta, impronta del certificato e codice monouso.
/// - Ogni connessione è HTTPS e accetta solo il certificato con quell'impronta (pinning): niente cloud,
///   niente autorità esterne, niente «fidati di tutto».
/// - Il segreto ricevuto all'abbinamento sta nel Portachiavi, solo su questo iPhone.
struct AbbinamentoPonte: Codable, Equatable {
    var nome: String
    var porta: Int
    var indirizzi: [String]
    /// SHA-256 del certificato del computer, base64url.
    var impronta: String
    var collegato: Date
    var ultimaSincronizzazione: Date?
}

enum ErrorePonte: LocalizedError {
    case qrNonValido, nonCollegato, irraggiungibile, rifiutato(String), risposta

    var errorDescription: String? {
        switch self {
        case .qrNonValido: "Questo non è il QR di Argo: su computer apri Incontri › Collega iPhone."
        case .nonCollegato: "Nessun computer collegato."
        case .irraggiungibile: "Non raggiungo Argo sul computer: deve essere aperto e sulla stessa rete."
        case .rifiutato(let motivo): motivo
        case .risposta: "Risposta inattesa da Argo sul computer."
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

        var nuovo = AbbinamentoPonte(nome: qr.n, porta: qr.p, indirizzi: qr.h, impronta: qr.f, collegato: .now)
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
                fatto.append("\(anagrafe.voci.count) voci aggiornate")
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
                fatto.append("\(pronte.count) incontr\(pronte.count == 1 ? "o inviato" : "i inviati")")
            }
            abbinamento?.ultimaSincronizzazione = .now
            return fatto.isEmpty ? nil : "Argo sul computer: " + fatto.joined(separator: ", ")
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
        guard let abbinamento, let segreto = Portachiavi.leggi() else { throw ErrorePonte.nonCollegato }
        let esito = try await richiesta(metodo, percorso, corpo: corpo, tipo: tipo, segreto: segreto,
                                        verso: abbinamento, attesa: attesa)
        // L'indirizzo che ha risposto va in cima: la prossima volta si prova per primo.
        if esito.1 != abbinamento.indirizzi.first {
            var aggiornato = abbinamento
            aggiornato.indirizzi = [esito.1] + abbinamento.indirizzi.filter { $0 != esito.1 }
            self.abbinamento = aggiornato
        }
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
                    throw ErrorePonte.rifiutato(motivo ?? "Argo sul computer ha risposto con errore \(http.statusCode).")
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
