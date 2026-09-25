import Foundation

/// Sinais da extensão pro app via Darwin notifications — funcionam entre processos
/// sem App Groups nem entitlements. Não carregam dados; o app só conta quantos chegaram.
enum SinalExtensao: String, CaseIterable {
    case iniciou       // transmissão começou
    case pedirAjustes       // extensão pede os ajustes (o app responde)
    case ajustesRecebidos   // chegou um conjunto válido de ajustes
    case leitura       // um frame passou pelo OCR
    case falhaOCR      // o Vision deu erro
    case oferta        // o parser achou uma oferta
    case aviso         // oferta nova: falou + notificou
    case corridaAceita // viu "Cheguei no local"/"Iniciar corrida" depois de uma oferta
    case corridaFeita  // viu "Finalizar corrida": entrou no relatório
    case terminou      // transmissão parou

    var nome: CFNotificationName {
        CFNotificationName("com.elias.app99.sinal.\(rawValue)" as CFString)
    }

    func enviar() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), nome, nil, nil, true)
    }
}
