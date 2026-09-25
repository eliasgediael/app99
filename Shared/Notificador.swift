import UserNotifications

/// Notificação local — garante o aviso mesmo se o áudio não tocar, e mostra os números
/// de um jeito que dá pra bater o olho.
enum Notificador {

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// 🟢 Corrida boa · ⭐ 4,95
    /// 💰 Lucro R$ 8,96 · R$ 1,08/km
    /// 📏 11,2 km no total
    static func enviar(_ a: AnaliseCorrida) {
        var titulo = "\(a.veredito.emoji) \(a.veredito.falado)"
        if let nota = a.oferta.notaPassageiro {
            titulo += " · ⭐ \(Formato.nota(nota))"
            if a.notaBaixa { titulo += " nota baixa" }
        }

        enviar(titulo: titulo,
               subtitulo: nil,
               corpo: "💰 Lucro \(Formato.reais(a.lucro)) · \(Formato.reais(a.ganhoPorKm))/km\n"
                    + "📏 \(Formato.km(a.kmTotal)) no total")
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
