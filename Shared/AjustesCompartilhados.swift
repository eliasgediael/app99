import Foundation

/// Leva os ajustes do app pra extensão (sem App Groups) pelo CanalDarwin.
enum AjustesCompartilhados {

    /// Campos em ordem fixa, em centésimos (0,35 → 35); depois vem a voz (0/1).
    private static let chaves = ["custoPorKm", "minimoPorKm", "bomPorKm", "alertaBuscaKm", "notaMinima", Narrador.chaveVelocidade]
    fileprivate static let canal = CanalDarwin(prefixo: "com.elias.app99.cfg", campos: chaves.count + 1)

    /// App: manda os ajustes atuais. Chamado quando a extensão pede e quando um ajuste muda.
    static func enviar() {
        let c = ConfigMoto.atual
        let decimais = [c.custoPorKm, c.minimoPorKm, c.bomPorKm, c.alertaBuscaKm, c.notaMinima, Narrador.velocidadeAtual]
        var campos = decimais.map { Int(($0 * 100).rounded()) }
        campos.append(Narrador.vozLigada ? 1 : 0)
        canal.enviar(campos)
    }

    /// Extensão: grava os valores recebidos no UserDefaults dela (mesmas chaves que o app usa).
    fileprivate static func aplicar(_ campos: [Int]) {
        let d = UserDefaults.standard
        for (i, chave) in chaves.enumerated() {
            d.set(Double(campos[i]) / 100, forKey: chave)
        }
        d.set(campos[chaves.count] == 1, forKey: Narrador.chaveFalar)
    }
}

/// Extensão: escuta os ajustes que o app manda.
final class ReceptorAjustes {
    static let shared = ReceptorAjustes()

    /// Chamado (na thread principal) cada vez que chega um conjunto válido.
    var aoReceber: (() -> Void)?

    private var receptor: ReceptorDarwin?

    func escutar() {
        guard receptor == nil else { return }
        receptor = ReceptorDarwin(canal: AjustesCompartilhados.canal) { [weak self] campos in
            AjustesCompartilhados.aplicar(campos)
            self?.aoReceber?()
        }
    }
}
