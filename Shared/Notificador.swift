import UserNotifications

/// Notificação local com a mesma frase da fala — garante o aviso mesmo se o áudio
/// não tocar dentro da extensão de gravação.
enum Notificador {

    static func pedirPermissao() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    static func enviar(_ frase: String) {
        let conteudo = UNMutableNotificationContent()
        conteudo.title = "Corrida 99"
        conteudo.body = frase
        conteudo.sound = .default

        // Identificador fixo: oferta nova substitui a anterior em vez de empilhar
        let pedido = UNNotificationRequest(identifier: "oferta99", content: conteudo, trigger: nil)
        UNUserNotificationCenter.current().add(pedido)
    }
}
