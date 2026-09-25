import Foundation

/// Avisos do app pra extensão (Darwin notifications, sem dados).
enum SinalApp: String, CaseIterable {
    /// App aberto na tela (repetido a cada poucos segundos): a extensão não lê,
    /// senão ela lê a própria tela do app (relatório, texto do teste) como se fosse a 99.
    case naFrente
    case saiu
    /// Print em tela cheia no teste: a extensão lê e avisa, mas não conta no relatório.
    case testeInicio
    case testeFim
    /// Apaga os números de hoje (ex.: depois de testes).
    case zerarHoje

    var nome: String { "com.elias.app99.app.\(rawValue)" }

    func enviar() { CanalDarwin.postar(nome) }
}
