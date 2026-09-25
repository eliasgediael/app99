import UIKit

/// Leva os ajustes do app pra extensão sem App Groups: uma área de transferência com nome
/// próprio só é visível pra apps do mesmo time de assinatura (o app e a extensão dele).
/// O app publica os valores do seu UserDefaults; a extensão copia pro UserDefaults dela
/// quando a transmissão começa, e aí `ConfigMoto.atual` e o `Narrador` funcionam igual.
enum AjustesCompartilhados {

    static let chaves = ["custoPorKm", "minimoPorKm", "bomPorKm", "alertaBuscaKm",
                         Narrador.chaveVelocidade, Narrador.chaveFalar]

    private static let nome = UIPasteboard.Name("com.elias.app99.ajustes")
    private static let tipo = "com.elias.app99.ajustes"

    /// App: grava os ajustes atuais.
    static func publicar() {
        let d = UserDefaults.standard
        var valores: [String: Any] = [:]
        for chave in chaves {
            if let v = d.object(forKey: chave) { valores[chave] = v }
        }
        guard let dados = try? PropertyListSerialization.data(fromPropertyList: valores, format: .binary, options: 0),
              let quadro = UIPasteboard(name: nome, create: true) else { return }
        quadro.setData(dados, forPasteboardType: tipo)
    }

    /// Extensão: copia os ajustes pro UserDefaults dela. Retorna false se não achou nada.
    @discardableResult
    static func receber() -> Bool {
        guard let quadro = UIPasteboard(name: nome, create: false),
              let dados = quadro.data(forPasteboardType: tipo),
              let valores = try? PropertyListSerialization.propertyList(from: dados, format: nil) as? [String: Any]
        else { return false }

        let d = UserDefaults.standard
        for chave in chaves {
            if let v = valores[chave] { d.set(v, forKey: chave) } else { d.removeObject(forKey: chave) }
        }
        return true
    }
}
