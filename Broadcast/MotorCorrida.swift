import Foundation

/// O que a leitura viu em um frame (já classificado).
enum TelaLida {
    case oferta(OfertaCorrida)
    case aCaminho            // "Cheguei no local"
    case embarque            // "Iniciar corrida": no local, esperando o passageiro
    case aBordo              // "Finalizar corrida": passageiro a bordo
    case fim(valorCent: Int?)
    case cancelada
    case outra

    /// Chave pra comparar frames (ofertas diferentes têm chaves diferentes).
    var classe: String {
        switch self {
        case .oferta(let o): return "oferta:" + MotorCorrida.chave(o)
        case .aCaminho:      return "aCaminho"
        case .embarque:      return "embarque"
        case .aBordo:        return "aBordo"
        case .fim:           return "fim"
        case .cancelada:     return "cancelada"
        case .outra:         return "outra"
        }
    }
}

/// Máquina de estados das corridas. É o ÚNICO lugar que decide estado e faturamento.
///
/// Regras:
/// - Oferta na tela / saindo da tela nunca vira corrida nem faturamento.
/// - Aceite só é ligado a uma oferta se a tela de aceite vier até 60 s depois de ela sair
///   da tela e nenhuma outra oferta tiver sido lida no meio. Na dúvida: sem valor.
/// - CONFIRMADA = aceite + valor + passageiro a bordo + tela de fim. Só ela soma no faturamento.
/// - ESTIMADA = aceite + valor + (a bordo OU fim). Soma separado.
/// - Resto = INDETERMINADA (R$ 0).
/// - Toda tela precisa ser lida 2 vezes em até 3 s pra valer (evita erro de OCR de um frame só).
///
/// Usar sempre na mesma fila (filaOCR).
final class MotorCorrida {

    private struct Corrida {
        let id: Int
        var estado: EstadoCorrida
        let criadaEm: Date
        var ultimaTela: Date
        var oferta: OfertaCorrida?
        var aceite: Bool
        var aBordo = false
        var fim = false
        var chegouEmbarque = false
        var valorFinalCent: Int?
    }

    private struct OfertaVista {
        let oferta: OfertaCorrida
        let chave: String
        let primeiraVez: Date
        var saiuEm: Date?
    }

    private let diario: Diario
    /// Custo por km atual (vem dos ajustes); usado no custo das corridas confirmadas.
    var custoPorKm: Double = ConfigMoto().custoPorKm

    private var abertas: [Corrida] = []
    private var ultimaOferta: OfertaVista?
    private var chavesAlheias: Set<String> = []           // ofertas lidas depois da última confirmada
    private var registradasEm: [String: Date] = [:]       // não repetir OFERTA_DETECTADA por 20 s

    private var classeAtual = "outra"
    private var candidata: (classe: String, tela: TelaLida, primeira: Date)?

    private let janelaDebounce: TimeInterval = 3
    private let janelaAceite: TimeInterval = 60
    private let limiteCorridaAberta: TimeInterval = 3 * 3600

    init(diario: Diario) {
        self.diario = diario
    }

    static func chave(_ o: OfertaCorrida) -> String {
        String(format: "%.2f|%.2f|%.2f", o.valor, o.kmAtePassageiro, o.kmViagem)
    }

    // MARK: Entrada

    func observar(_ tela: TelaLida, em agora: Date = Date()) {
        encerrarVelhas(agora)

        // Qualquer oferta lida, mesmo num frame só, conta pra ambiguidade do aceite
        if case .oferta(let o) = tela {
            let chave = Self.chave(o)
            if chave != ultimaOferta?.chave { chavesAlheias.insert(chave) }
        }

        let classe = tela.classe
        if classe == classeAtual {
            candidata = nil
            return
        }
        if let c = candidata, c.classe == classe, agora.timeIntervalSince(c.primeira) <= janelaDebounce {
            let anterior = classeAtual
            classeAtual = classe
            candidata = nil
            mudou(de: anterior, para: tela, em: agora)
        } else {
            candidata = (classe, tela, agora)
        }
    }

    /// Leitura desligando: fecha o que estiver aberto com o que se sabe.
    func encerrarTudo(em agora: Date = Date()) {
        for c in abertas { encerrar(c, em: agora, porque: .leituraEncerrada) }
        abertas.removeAll()
        classeAtual = "outra"
        candidata = nil
        ultimaOferta = nil
        chavesAlheias = []
    }

    /// Usuário zerou o dia: esquece o que estava em andamento.
    func esquecer() {
        abertas.removeAll()
        ultimaOferta = nil
        chavesAlheias = []
    }

    // MARK: Transições

    private func mudou(de anterior: String, para tela: TelaLida, em agora: Date) {
        // Oferta saindo da tela: só registra. NUNCA vira corrida nem faturamento.
        if anterior.hasPrefix("oferta:"), var ov = ultimaOferta, anterior == "oferta:" + ov.chave, ov.saiuEm == nil {
            ov.saiuEm = agora
            ultimaOferta = ov
            switch tela {
            case .aCaminho, .embarque: break   // o aceite registra
            default:
                evento(.ofertaSaiuDaTela, .tela, em: agora, motivo: .ofertaSaiuSemAceite, oferta: ov.oferta)
            }
        }

        switch tela {
        case .oferta(let o):          ofertaNaTela(o, em: agora)
        case .aCaminho:               telaDeAceite(embarque: false, em: agora)
        case .embarque:               telaDeAceite(embarque: true, em: agora)
        case .aBordo:                 passageiroABordo(em: agora)
        case .fim(let valorCent):     fimDeCorrida(valorCent: valorCent, em: agora)
        case .cancelada:              cancelamento(em: agora)
        case .outra:                  break
        }
    }

    private func ofertaNaTela(_ o: OfertaCorrida, em agora: Date) {
        let chave = Self.chave(o)
        ultimaOferta = OfertaVista(oferta: o, chave: chave, primeiraVez: agora)
        chavesAlheias = []

        registradasEm = registradasEm.filter { agora.timeIntervalSince($0.value) < 20 }
        guard registradasEm[chave] == nil else { return }
        registradasEm[chave] = agora
        diario.contarOferta()
        evento(.ofertaDetectada, .tela, em: agora, motivo: .lidoNaTela, oferta: o)
    }

    private func telaDeAceite(embarque: Bool, em agora: Date) {
        // Corrida já aceita e ainda sem passageiro: é a mesma, a menos que uma oferta nova tenha
        // aparecido depois da última tela dela (aí foi outro aceite)
        if let i = abertas.lastIndex(where: { $0.estado == .aceita || $0.estado == .aCaminho }) {
            let ofertaNova = ultimaOferta.map { $0.primeiraVez > abertas[i].ultimaTela } ?? false
            if !ofertaNova {
                abertas[i].ultimaTela = agora
                if embarque && !abertas[i].chegouEmbarque {
                    abertas[i].chegouEmbarque = true
                    evento(.telaEmbarque, .tela, em: agora, corrida: abertas[i].id, motivo: .mesmaCorridaNaTela)
                }
                return
            }
            let velha = abertas.remove(at: i)
            encerrar(velha, em: agora, porque: .substituidaPorNovoAceite)
        }

        // Novo aceite: tenta ligar à oferta
        var ligada: OfertaCorrida?
        var motivo = MotivoEvento.aceiteSemOferta
        var segundos = 0
        if let ov = ultimaOferta {
            let saiu = ov.saiuEm ?? agora
            segundos = Int(agora.timeIntervalSince(saiu))
            if agora.timeIntervalSince(saiu) <= janelaAceite {
                if chavesAlheias.isEmpty {
                    ligada = ov.oferta
                    motivo = .ofertaLigadaAoAceite
                } else {
                    motivo = .aceiteOfertaAmbigua
                }
            }
        }
        ultimaOferta = nil
        chavesAlheias = []

        let id = diario.novoIdCorrida()
        var c = Corrida(id: id, estado: .aceita, criadaEm: agora, ultimaTela: agora, oferta: ligada, aceite: true)
        evento(.aceiteDetectado, .tela, em: agora, corrida: id, para: .aceita,
               motivo: motivo, extra: motivo == .ofertaLigadaAoAceite ? segundos : 0, oferta: ligada)
        evento(.transicao, .tela, em: agora, corrida: id, de: .aceita, para: .aCaminho, motivo: .lidoNaTela)
        c.estado = .aCaminho
        if embarque {
            c.chegouEmbarque = true
            evento(.telaEmbarque, .tela, em: agora, corrida: id, motivo: .lidoNaTela)
        }
        abertas.append(c)
        SinalExtensao.corridaAceita.enviar()
    }

    private func passageiroABordo(em agora: Date) {
        if let i = abertas.firstIndex(where: { $0.estado == .aceita || $0.estado == .aCaminho }) {
            let de = abertas[i].estado
            abertas[i].aBordo = true
            abertas[i].ultimaTela = agora
            let id = abertas[i].id
            evento(.passageiroABordo, .tela, em: agora, corrida: id, motivo: .lidoNaTela)
            evento(.transicao, .tela, em: agora, corrida: id, de: de, para: .passageiroABordo, motivo: .lidoNaTela)
            evento(.transicao, .inferencia, em: agora, corrida: id, de: .passageiroABordo, para: .emCorrida,
                   motivo: .aBordoImplicaEmCorrida)
            abertas[i].estado = .emCorrida
            return
        }
        if let i = abertas.lastIndex(where: { $0.estado == .emCorrida }) {
            abertas[i].ultimaTela = agora   // mesma corrida voltando pra tela
            return
        }
        // A bordo sem aceite: registra, mas nunca vai ter valor confirmado
        let id = diario.novoIdCorrida()
        var c = Corrida(id: id, estado: .passageiroABordo, criadaEm: agora, ultimaTela: agora, oferta: nil, aceite: false)
        c.aBordo = true
        evento(.passageiroABordo, .tela, em: agora, corrida: id, para: .passageiroABordo, motivo: .aBordoSemAceite)
        evento(.transicao, .inferencia, em: agora, corrida: id, de: .passageiroABordo, para: .emCorrida,
               motivo: .aBordoImplicaEmCorrida)
        c.estado = .emCorrida
        abertas.append(c)
    }

    private func fimDeCorrida(valorCent: Int?, em agora: Date) {
        let i = abertas.firstIndex(where: { $0.estado == .emCorrida })
            ?? abertas.lastIndex(where: { $0.estado == .aceita || $0.estado == .aCaminho })
        guard let i else {
            evento(.fimDetectado, .tela, em: agora, motivo: .fimSemCorridaAberta, valorCent: valorCent ?? 0)
            return
        }
        var c = abertas.remove(at: i)
        c.fim = true
        c.valorFinalCent = valorCent
        evento(.fimDetectado, .tela, em: agora, corrida: c.id,
               motivo: valorCent != nil ? .valorFinalLidoNaTela : .lidoNaTela, valorCent: valorCent ?? 0)
        evento(.transicao, .tela, em: agora, corrida: c.id, de: c.estado, para: .fimDetectado, motivo: .lidoNaTela)
        c.estado = .fimDetectado
        encerrar(c, em: agora, porque: nil)
    }

    private func cancelamento(em agora: Date) {
        guard let i = abertas.lastIndex(where: { $0.estado == .aceita || $0.estado == .aCaminho }) else {
            evento(.cancelamentoDetectado, .tela, em: agora, motivo: .cancelamentoSemCorrida)
            return
        }
        let c = abertas.remove(at: i)
        evento(.cancelamentoDetectado, .tela, em: agora, corrida: c.id, motivo: .lidoNaTela)
        evento(.transicao, .tela, em: agora, corrida: c.id, de: c.estado, para: .cancelada, motivo: .canceladaNaTela)
        evento(.semFaturamento, .inferencia, em: agora, corrida: c.id, motivo: .canceladaNaTela)
    }

    private func encerrarVelhas(_ agora: Date) {
        let velhas = abertas.filter { agora.timeIntervalSince($0.criadaEm) > limiteCorridaAberta }
        guard !velhas.isEmpty else { return }
        abertas.removeAll { agora.timeIntervalSince($0.criadaEm) > limiteCorridaAberta }
        for c in velhas { encerrar(c, em: agora, porque: .tempoEsgotado) }
    }

    // MARK: Decisão final

    /// Classifica pela evidência e só aí mexe em dinheiro. `porque` = motivo de fechar sem tela de fim.
    private func encerrar(_ c: Corrida, em agora: Date, porque: MotivoEvento?) {
        let valorCent = c.valorFinalCent ?? c.oferta.map { Int(($0.valor * 100).rounded()) }

        var falta = 0
        if !c.aceite { falta |= Falta.aceite }
        if valorCent == nil { falta |= Falta.valor }
        if !c.aBordo { falta |= Falta.aBordo }
        if !c.fim { falta |= Falta.fim }

        let final: EstadoCorrida
        let confianca: Confianca
        if falta == 0 {
            final = .confirmada; confianca = .confirmado
        } else if c.aceite && valorCent != nil && (c.aBordo || c.fim) {
            final = .estimada; confianca = .estimado
        } else {
            final = .indeterminada; confianca = .indeterminado
        }

        let motivo = porque ?? (falta == 0 ? .evidenciaCompleta : .evidenciaIncompleta)
        evento(.transicao, .inferencia, em: agora, corrida: c.id, de: c.estado, para: final,
               confianca: confianca, motivo: motivo, extra: falta, oferta: c.oferta)

        switch final {
        case .confirmada:
            let km = c.oferta.map { $0.kmAtePassageiro + $0.kmViagem } ?? 0
            diario.somarConfirmada(valorCent: valorCent ?? 0,
                                   custoCent: Int((km * custoPorKm * 100).rounded()),
                                   metros: Int((km * 1000).rounded()))
            evento(.faturamentoConfirmado, .inferencia, em: agora, corrida: c.id, confianca: .confirmado,
                   motivo: .evidenciaCompleta, valorCent: valorCent ?? 0)
            SinalExtensao.corridaFeita.enviar()
        case .estimada:
            diario.somarEstimada(valorCent: valorCent ?? 0)
            evento(.faturamentoEstimado, .inferencia, em: agora, corrida: c.id, confianca: .estimado,
                   motivo: .evidenciaIncompleta, extra: falta, valorCent: valorCent ?? 0)
        default:
            evento(.semFaturamento, .inferencia, em: agora, corrida: c.id, confianca: .indeterminado,
                   motivo: .evidenciaIncompleta, extra: falta)
        }
    }

    // MARK: Evento

    private func evento(_ tipo: TipoEvento, _ origem: OrigemEvento, em agora: Date,
                        corrida: Int = 0, de: EstadoCorrida? = nil, para: EstadoCorrida? = nil,
                        confianca: Confianca? = nil, motivo: MotivoEvento = .nenhum, extra: Int = 0,
                        oferta: OfertaCorrida? = nil, valorCent: Int = 0) {
        var e = EventoLinha(seq: 0, em: agora, tipo: tipo, origem: origem)
        e.corrida = corrida
        e.estadoAnterior = de
        e.estadoNovo = para
        e.confianca = confianca
        e.motivo = motivo
        e.extra = extra
        e.valorCent = valorCent
        if let o = oferta {
            if valorCent == 0 { e.valorCent = Int((o.valor * 100).rounded()) }
            e.buscaM = Int((o.kmAtePassageiro * 1000).rounded())
            e.viagemM = Int((o.kmViagem * 1000).rounded())
            e.nota100 = o.notaPassageiro.map { Int(($0 * 100).rounded()) } ?? 0
        }
        diario.adicionar(e)
    }
}
