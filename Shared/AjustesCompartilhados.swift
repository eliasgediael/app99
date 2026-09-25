import Foundation

/// Leva os ajustes do app pra extensão sem App Groups, usando Darwin notifications
/// (o mesmo canal dos sinais de status, que já funciona entre os dois processos).
///
/// Darwin notifications não carregam dados, então os números vão bit a bit:
/// `cfg.inicio` → um aviso `cfg.b.<campo>.<bit>` pra cada bit 1 → `cfg.fim`.
/// O último campo é uma soma de conferência; a extensão só aplica se bater.
enum AjustesCompartilhados {

    fileprivate static let prefixo = "com.elias.app99.cfg"
    fileprivate static let bitsPorCampo = 16
    fileprivate static let nomeInicio = prefixo + ".inicio"
    fileprivate static let nomeFim = prefixo + ".fim"
    fileprivate static func nomeBit(_ campo: Int, _ bit: Int) -> String { "\(prefixo).b.\(campo).\(bit)" }

    /// Campos em ordem fixa, em centésimos (0,35 → 35).
    private static let chaves = ["custoPorKm", "minimoPorKm", "bomPorKm", "alertaBuscaKm", Narrador.chaveVelocidade]
    fileprivate static let totalCampos = chaves.count + 2   // + voz ligada + conferência

    // MARK: App → envia

    /// App: manda os ajustes atuais. Chamado quando a extensão pede e quando um ajuste muda.
    static func enviar() {
        let c = ConfigMoto.atual
        let decimais = [c.custoPorKm, c.minimoPorKm, c.bomPorKm, c.alertaBuscaKm, Narrador.velocidadeAtual]
        var campos = decimais.map { Int(($0 * 100).rounded()) & 0xFFFF }
        campos.append(Narrador.vozLigada ? 1 : 0)
        campos.append(conferencia(campos))

        postar(nomeInicio)
        for (i, valor) in campos.enumerated() {
            for bit in 0..<bitsPorCampo where valor & (1 << bit) != 0 {
                postar(nomeBit(i, bit))
            }
        }
        postar(nomeFim)
    }

    fileprivate static func conferencia(_ campos: [Int]) -> Int {
        // Soma ponderada: pega bit perdido e campo trocado
        campos.enumerated().reduce(0) { ($0 + ($1.offset + 1) * $1.element) & 0xFFFF } ^ 0xA55A
    }

    private static func postar(_ nome: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(nome as CFString), nil, nil, true)
    }

    // MARK: Extensão → recebe

    /// Grava os valores recebidos no UserDefaults da extensão (mesmas chaves que o app usa).
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

    private var campos: [Int] = []
    private var escutando = false

    func escutar() {
        guard !escutando else { return }
        escutando = true

        typealias A = AjustesCompartilhados
        var nomes = [A.nomeInicio, A.nomeFim]
        for i in 0..<A.totalCampos {
            for bit in 0..<A.bitsPorCampo { nomes.append(A.nomeBit(i, bit)) }
        }

        let centro = CFNotificationCenterGetDarwinNotifyCenter()
        let observador = Unmanaged.passUnretained(self).toOpaque()   // singleton, nunca é liberado
        for nome in nomes {
            CFNotificationCenterAddObserver(centro, observador, { _, observador, nome, _, _ in
                guard let observador, let nome else { return }
                Unmanaged<ReceptorAjustes>.fromOpaque(observador).takeUnretainedValue()
                    .recebeu(nome.rawValue as String)
            }, nome as CFString, nil, .deliverImmediately)
        }
    }

    private func recebeu(_ nome: String) {
        typealias A = AjustesCompartilhados
        if nome == A.nomeInicio {
            campos = Array(repeating: 0, count: A.totalCampos)
        } else if nome == A.nomeFim {
            guard campos.count == A.totalCampos,
                  A.conferencia(Array(campos.dropLast())) == campos.last else { return }
            A.aplicar(campos)
            aoReceber?()
        } else if !campos.isEmpty {
            let partes = nome.dropFirst(A.prefixo.count + 3).split(separator: ".")   // "<campo>.<bit>"
            if partes.count == 2, let i = Int(partes[0]), let bit = Int(partes[1]), i < campos.count {
                campos[i] |= 1 << bit
            }
        }
    }
}
