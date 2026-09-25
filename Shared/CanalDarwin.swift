import Foundation

/// Manda pacotes de números entre o app e a extensão sem App Groups, via Darwin notifications.
///
/// Darwin notifications não carregam dados, então cada número vai bit a bit:
/// `<prefixo>.inicio` → um aviso `<prefixo>.b.<campo>.<bit>` pra cada bit 1 → `<prefixo>.fim`.
/// O último campo é uma soma de conferência; quem recebe só aceita se bater.
struct CanalDarwin {
    let prefixo: String
    let campos: Int          // sem contar a conferência

    static let bits = 32

    fileprivate var nomeInicio: String { prefixo + ".inicio" }
    fileprivate var nomeFim: String { prefixo + ".fim" }
    fileprivate func nomeBit(_ campo: Int, _ bit: Int) -> String { "\(prefixo).b.\(campo).\(bit)" }

    fileprivate var todosOsNomes: [String] {
        var nomes = [nomeInicio, nomeFim]
        for i in 0...campos {
            for bit in 0..<Self.bits { nomes.append(nomeBit(i, bit)) }
        }
        return nomes
    }

    func enviar(_ valores: [Int]) {
        guard valores.count == campos else { return }
        var todos = valores.map { $0 & 0xFFFF_FFFF }
        todos.append(Self.conferencia(todos))

        Self.postar(nomeInicio)
        for (i, valor) in todos.enumerated() {
            for bit in 0..<Self.bits where valor & (1 << bit) != 0 {
                Self.postar(nomeBit(i, bit))
            }
        }
        Self.postar(nomeFim)
    }

    fileprivate static func conferencia(_ valores: [Int]) -> Int {
        // Soma ponderada: pega bit perdido e campo trocado
        valores.enumerated().reduce(0) { ($0 + ($1.offset + 1) * $1.element) & 0xFFFF_FFFF } ^ 0xA55A_5AA5
    }

    static func postar(_ nome: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(nome as CFString), nil, nil, true)
    }
}

/// Escuta um canal. Precisa ficar vivo enquanto for usado (guarde numa propriedade estática/singleton).
/// `aoReceber` roda na thread principal, com os campos (sem a conferência).
final class ReceptorDarwin {
    private let canal: CanalDarwin
    private let aoReceber: ([Int]) -> Void
    private var recebendo: [Int] = []

    init(canal: CanalDarwin, aoReceber: @escaping ([Int]) -> Void) {
        self.canal = canal
        self.aoReceber = aoReceber

        let centro = CFNotificationCenterGetDarwinNotifyCenter()
        let observador = Unmanaged.passUnretained(self).toOpaque()
        for nome in canal.todosOsNomes {
            CFNotificationCenterAddObserver(centro, observador, { _, observador, nome, _, _ in
                guard let observador, let nome else { return }
                Unmanaged<ReceptorDarwin>.fromOpaque(observador).takeUnretainedValue()
                    .recebeu(nome.rawValue as String)
            }, nome as CFString, nil, .deliverImmediately)
        }
    }

    private func recebeu(_ nome: String) {
        if nome == canal.nomeInicio {
            recebendo = Array(repeating: 0, count: canal.campos + 1)
        } else if nome == canal.nomeFim {
            guard recebendo.count == canal.campos + 1,
                  CanalDarwin.conferencia(Array(recebendo.dropLast())) == recebendo.last else { return }
            let valores = Array(recebendo.dropLast())
            recebendo = []
            aoReceber(valores)
        } else if !recebendo.isEmpty {
            let partes = nome.dropFirst(canal.prefixo.count + 3).split(separator: ".")   // "<campo>.<bit>"
            if partes.count == 2, let i = Int(partes[0]), let bit = Int(partes[1]), i < recebendo.count {
                recebendo[i] |= 1 << bit
            }
        }
    }
}

/// Escuta um aviso Darwin simples (sem dados). Precisa ficar vivo enquanto for usado.
/// `acao` roda na thread principal.
final class ObservadorDarwin {
    private let acao: () -> Void

    init(_ nome: String, acao: @escaping () -> Void) {
        self.acao = acao
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        Unmanaged.passUnretained(self).toOpaque(), { _, observador, _, _, _ in
            guard let observador else { return }
            Unmanaged<ObservadorDarwin>.fromOpaque(observador).takeUnretainedValue().acao()
        }, nome as CFString, nil, .deliverImmediately)
    }
}
