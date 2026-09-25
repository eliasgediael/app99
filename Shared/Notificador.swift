import UserNotifications

/// Notificação local — garante o aviso mesmo se o áudio não tocar, e mostra os números
/// de um jeito que dá pra bater o olho.
enum Notificador {

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// 🟢 Corrida boa · R$ 2,60/km
    /// R$ 13,50 · 5,2 km no total
    /// 💰 Lucro R$ 11,68 · R$ 43,80/h
    /// 📍 Busca 1,2 km · 🏁 Viagem 4,0 km
    static func enviar(_ a: AnaliseCorrida) {
        let o = a.oferta

        var lucro = "💰 Lucro \(Formato.reais(a.lucro))"
        if let porHora = a.ganhoPorHora {
            lucro += " · \(Formato.reais(porHora))/h"
        }
        var busca = "📍 Busca \(Formato.km(o.kmAtePassageiro))"
        if a.buscaLonga { busca += " ⚠️" }

        enviar(titulo: "\(a.veredito.emoji) \(a.veredito.falado) · \(Formato.reais(a.ganhoPorKm))/km",
               subtitulo: "\(Formato.reais(o.valor)) · \(Formato.km(a.kmTotal)) no total",
               corpo: "\(lucro)\n\(busca) · 🏁 Viagem \(Formato.km(o.kmViagem))")
    }

    static func enviar(_ frase: String) {
        enviar(titulo: "App 99", subtitulo: nil, corpo: frase)
    }

    private static func enviar(titulo: String, subtitulo: String?, corpo: String) {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = titulo
        if let subtitulo { conteudo.subtitle = subtitulo }
        conteudo.body = corpo
        conteudo.sound = .default

        // Identificador fixo: oferta nova substitui a anterior em vez de empilhar
        let pedido = UNNotificationRequest(identifier: "oferta99", content: conteudo, trigger: nil)
        UNUserNotificationCenter.current().add(pedido)
    }
}

extension Veredito {
    var emoji: String {
        switch self {
        case .boa:       return "🟢"
        case .aceitavel: return "🟡"
        case .ruim:      return "🔴"
        }
    }
}
