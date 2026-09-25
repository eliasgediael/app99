import UserNotifications

/// Notificação local — garante o aviso mesmo se o áudio não tocar, e mostra os números
/// de um jeito que dá pra bater o olho.
enum Notificador {

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// 🟢 Corrida boa · ⭐ 4,95
    /// 💵 R$ 12,10 · 💰 Lucro R$ 8,18
    /// 📊 R$ 1,08/km · 📏 11,2 km
    static func enviar(_ a: AnaliseCorrida) {
        var titulo = "\(a.veredito.emoji) \(a.veredito.falado)"
        if let nota = a.oferta.notaPassageiro {
            titulo += " · ⭐ \(Formato.nota(nota))"
            if a.notaBaixa { titulo += " nota baixa" }
        }

        enviar(titulo: titulo,
               subtitulo: nil,
               corpo: "💵 \(Formato.reais(a.oferta.valor)) · 💰 Lucro \(Formato.reais(a.lucro))\n"
                    + "📊 \(Formato.reais(a.ganhoPorKm))/km · 📏 \(Formato.km(a.kmTotal))")
    }

    static func enviar(_ frase: String) {
        enviar(titulo: "App 99", subtitulo: nil, corpo: frase)
    }

    /// 📋 Resumo de hoje
    /// 💵 R$ 186,40 · 💰 Lucro R$ 156,65
    /// 🛵 14 corridas · 85 km · ✅ 14 de 41 ofertas
    static func enviarResumo(_ d: DiaRelatorio) {
        enviar(titulo: "📋 Resumo de hoje",
               subtitulo: nil,
               corpo: "💵 \(Formato.reais(d.faturado)) · 💰 Lucro \(Formato.reais(d.lucro))\n"
                    + "🛵 \(d.corridas) corrida\(d.corridas == 1 ? "" : "s") · \(Formato.km(d.km)) · ✅ \(d.corridas) de \(d.ofertas) ofertas",
               id: "resumo99")
    }

    private static func enviar(titulo: String, subtitulo: String?, corpo: String, id: String = "oferta99") {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = titulo
        if let subtitulo { conteudo.subtitle = subtitulo }
        conteudo.body = corpo
        conteudo.sound = .default

        // Identificador fixo: oferta nova substitui a anterior em vez de empilhar
        let pedido = UNNotificationRequest(identifier: id, content: conteudo, trigger: nil)
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
