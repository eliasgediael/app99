import Foundation

/// Turnos gravados antes da correção do motor (corridas partidas em pedaços) são refeitos
/// uma vez, com o MESMO MotorCorrida da leitura: as telas lidas são repassadas ao motor
/// e as decisões antigas são trocadas pelas novas. Leituras de tela e GPS não mudam.
///
/// Os seqs positivos nunca somem do arquivo: o app pede à extensão "tudo depois do último
/// seq contíguo", e um buraco faria as decisões antigas voltarem.
@MainActor
enum Reprocessamento {
    private static let chaveFeito = "reprocessamento-motor-v1"
    /// 26/09/2026 02:00 (UTC−4): versões anteriores do motor partiam as corridas.
    private static let corte = Date(timeIntervalSince1970: 1_790_402_400)

    static func executarSeNecessario() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: chaveFeito) else { return }
        let linha = LinhaDoTempoStore.shared
        let alvos = TurnoStore.shared.turnos.filter { t in
            guard let fim = t.fim, fim < corte else { return false }
            return linha.eventos.contains { $0.corrida > 0 && t.contem($0.data) }
        }
        var eventos = linha.eventos
        var mudou = false
        for t in alvos {
            if let novos = refazer(t, eventos: eventos) {
                eventos = novos
                mudou = true
            }
        }
        if mudou { linha.substituirTudo(eventos, copiaDeSeguranca: "linha-do-tempo-antes-do-reprocessamento.json") }
        d.set(true, forKey: chaveFeito)
    }

    /// Devolve a linha do tempo inteira com as decisões do turno refeitas, ou nil se algo não fechar.
    static func refazer(_ turno: Turno, eventos todos: [EventoLinha]) -> [EventoLinha]? {
        let tela = todos.filter { $0.seq > 0 && turno.contem($0.data) }.sorted { $0.seq < $1.seq }
        guard !tela.isEmpty else { return nil }

        let registro = RegistroReplay(primeiraCorrida: 1)
        let motor = MotorCorrida(diario: registro)

        for (k, e) in tela.enumerated() {
            let proximo = k + 1 < tela.count ? tela[k + 1] : nil
            let lida: TelaLida
            switch e.tipo {
            case .ofertaDetectada:
                guard e.oferta > 0 else { continue }
                registro.proximaOferta = e.oferta
                lida = .oferta(OfertaCorrida(valor: Double(e.valorCent) / 100,
                                             kmAtePassageiro: Double(e.buscaM) / 1000,
                                             kmViagem: Double(e.viagemM) / 1000,
                                             minAtePassageiro: e.minutos > 0 ? e.minutos / 1000 : nil,
                                             minViagem: e.minutos > 0 ? e.minutos % 1000 : nil,
                                             notaPassageiro: e.nota100 > 0 ? Double(e.nota100) / 100 : nil,
                                             textoBruto: ""))
            case .ofertaSaiuDaTela:
                // Registrado junto com a troca direta por outra oferta ou com o "cancelou": não é outra tela
                if let p = proximo, p.tipo == .ofertaDetectada || p.tipo == .cancelamentoDetectado, p.em - e.em <= 1 { continue }
                lida = .outra
            case .aceiteDetectado where e.origem == .tela: lida = .aCaminho
            case .telaEmbarque:          lida = .embarque
            case .passageiroABordo:      lida = .aBordo
            case .fimDetectado:          lida = .fim(valorCent: e.motivo == .valorFinalLidoNaTela && e.valorCent > 0 ? e.valorCent : nil)
            case .cancelamentoDetectado: lida = .cancelada
            case .leituraEncerrada:
                motor.encerrarTudo(em: e.data)
                continue
            default:
                continue
            }
            // A leitura só aceita uma tela vista 2 vezes (evita erro de um frame só)
            motor.observar(lida, em: e.data)
            motor.observar(lida, em: e.data)
        }

        let decisoes = registro.eventos.filter { $0.tipo != .ofertaDetectada && $0.tipo != .ofertaSaiuDaTela }
        let tiposMotor: Set<TipoEvento> = [.aceiteDetectado, .telaEmbarque, .passageiroABordo, .fimDetectado,
                                          .cancelamentoDetectado, .transicao, .faturamentoConfirmado,
                                          .faturamentoEstimado, .semFaturamento]
        let tiposTela: Set<TipoEvento> = [.aceiteDetectado, .telaEmbarque, .passageiroABordo, .fimDetectado, .cancelamentoDetectado]
        let antigos = tela.filter { tiposMotor.contains($0.tipo) }
        var livres = Set(antigos.map(\.seq))
        var porSeq = Dictionary(uniqueKeysWithValues: todos.map { ($0.seq, $0) })

        // 1) Evento de tela: mesmo seq e mesmo GPS do original (mesmo tipo e mesmo segundo)
        var origem: [Int: Int] = [:]   // índice em `decisoes` → seq original
        for (i, e) in decisoes.enumerated() where e.origem == .tela && tiposTela.contains(e.tipo) {
            if let a = antigos.first(where: { livres.contains($0.seq) && $0.tipo == e.tipo && $0.em == e.em }) {
                origem[i] = a.seq
                livres.remove(a.seq)
            }
        }

        // 2) O resto reaproveita seqs antigos; no mesmo segundo, antes do evento de tela
        var disponiveis = livres.sorted()
        var negativo = min(-2_000_000, (todos.map(\.seq).min() ?? 0) - 1_000_000)
        var novos: [EventoLinha] = []
        var i = 0
        while i < decisoes.count {
            var j = i
            while j < decisoes.count && decisoes[j].em == decisoes[i].em { j += 1 }
            let grupo = Array(i..<j)
            let soltos = grupo.filter { origem[$0] == nil }
            let fixos = grupo.compactMap { origem[$0] }
            var seqs: [Int] = []
            if soltos.count <= disponiveis.count {
                let cand = Array(disponiveis.prefix(soltos.count))
                if fixos.isEmpty || (cand.max() ?? Int.min) < (fixos.min() ?? Int.max) {
                    seqs = cand
                    disponiveis.removeFirst(soltos.count)
                }
            }
            if seqs.count != soltos.count {
                seqs = soltos.map { _ in defer { negativo += 1 }; return negativo }
            }
            for (k, idx) in soltos.enumerated() {
                var e = decisoes[idx]
                e.seq = seqs[k]
                novos.append(e)
            }
            for idx in grupo {
                guard let s = origem[idx], let base = porSeq[s] else { continue }
                var e = decisoes[idx]
                e.seq = s
                e.lat = base.lat; e.lon = base.lon; e.precisaoM = base.precisaoM; e.kmTurno = base.kmTurno
                novos.append(e)
            }
            i = j
        }

        // 3) Decisões antigas que sobraram ficam no lugar, sem efeito
        for s in disponiveis {
            guard let base = porSeq[s] else { continue }
            var e = EventoLinha(seq: s, em: base.data, tipo: .semFaturamento, origem: .inferencia)
            e.texto = "Decisão antiga refeita"
            novos.append(e)
        }

        for s in antigos.map(\.seq) { porSeq.removeValue(forKey: s) }
        for e in novos { porSeq[e.seq] = e }
        let resultado = porSeq.values.sorted { $0.seq < $1.seq }

        // Conferências: nenhum seq sumiu, nada fora do turno mudou, e o motor produziu corridas
        let antes = Set(todos.map(\.seq))
        guard antes.isSubset(of: Set(resultado.map(\.seq))) else { return nil }
        let fora = todos.filter { !turno.contem($0.data) }
        guard fora.allSatisfy({ porSeq[$0.seq] == $0 }) else { return nil }
        guard novos.contains(where: { $0.tipo == .transicao && $0.estadoNovo?.encerrada == true }) else { return nil }
        return resultado
    }
}

/// Registro em memória pro reprocessamento: não soma o relatório do dia nem avisa o app.
final class RegistroReplay: RegistroMotor {
    private(set) var eventos: [EventoLinha] = []
    var proximaOferta = 0
    private var ultimaCorrida: Int

    init(primeiraCorrida: Int) { ultimaCorrida = primeiraCorrida - 1 }

    func novoIdOferta() -> Int { proximaOferta }
    func novoIdCorrida() -> Int { ultimaCorrida += 1; return ultimaCorrida }
    func contarOferta() {}
    func somarConfirmada(valorCent: Int, custoCent: Int, metros: Int) {}
    func somarEstimada(valorCent: Int) {}
    func adicionar(_ evento: EventoLinha) { eventos.append(evento) }
    func sinal(_ s: SinalExtensao) {}
}
