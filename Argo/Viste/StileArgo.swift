import SwiftUI

/// Colori dello «Stile Argo», gli stessi di Argo sul computer (tema Notte, `app/tema.py`):
/// terracotta come accento (AccentColor), salvia per «fatto», ocra per gli avvisi,
/// e la stessa tavolozza dei parlanti, così una voce ha lo stesso colore su iPhone e computer.
/// Il colore non è mai l'unico segnale: c'è sempre anche un'icona o un testo.
enum StileArgo {
    static let ok = Color(red: 0.612, green: 0.788, blue: 0.651)      // #9CC9A6
    static let avviso = Color(red: 0.933, green: 0.761, blue: 0.608)  // #EEC29B
    static let parlanti: [Color] = [
        Color(red: 0.898, green: 0.502, blue: 0.455),  // #E58074
        Color(red: 0.933, green: 0.761, blue: 0.608),  // #EEC29B
        Color(red: 0.561, green: 0.702, blue: 0.769),  // #8FB3C4
        Color(red: 0.663, green: 0.765, blue: 0.627),  // #A9C3A0
        Color(red: 0.780, green: 0.635, blue: 0.753),  // #C7A2C0
        Color(red: 0.851, green: 0.722, blue: 0.561),  // #D9B88F
        Color(red: 0.941, green: 0.659, blue: 0.627),  // #F0A8A0
        Color(red: 0.624, green: 0.776, blue: 0.745),  // #9FC6BE
    ]
}
