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

/// Quem guarda o que o motor decide. Na leitura da tela é o Diario; no app, o reprocessamento de turnos antigos.
protocol RegistroMotor: AnyObject {
    func novoIdOferta() -> Int
    func novoIdCorrida() -> Int
    func contarOferta()
    func somarConfirmada(valorCent: Int, custoCent: Int, metros: Int)
    func somarEstimada(valorCent: Int)
    func adicionar(_ evento: EventoLinha)
    func sinal(_ s: SinalExtensao)
}

/// Máquina de estados das corridas. É o ÚNICO lugar que decide estado e faturamento.
///
/// Regras:
/// - Oferta na tela / saindo da tela nunca vira corrida nem faturamento.
/// - Aceite só é ligado a uma oferta se a tela de aceite vier até 60 s depois de ela sair
///   da tela e nenhuma outra oferta tiver sido lida no meio. Na dúvida: sem valor.
/// - Durante uma corrida, a 99 mostra "cancelou" logo depois de cada oferta que você NÃO aceita.
///   Por isso: "cancelou" até 8 s depois de uma oferta sair vale pra oferta, nunca pra sua corrida;
///   e a oferta que sai SEM esse aviso com corrida em andamento foi aceita (vai pra fila da próxima).
/// - A 99 só mostra a tela de aceite da próxima corrida depois de você finalizar a atual:
///   aceite novo com corrida em andamento ⇒ a anterior terminou (inferência marcada).
/// - CONFIRMADA = aceite + valor + passageiro a bordo + tela de fim. Só ela soma no faturamento.
///   (A tela de fim implica passageiro a bordo.)
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
        var ofertaId = 0
        var ligacaoConfirmada = false    // aceite até 10 s depois da oferta sair da tela
        var aceite: Bool
        var aBordo = false
        var fim = false
        var chegouEmbarque = false
        var valorFinalCent: Int?
    }

    private struct OfertaVista {
        let oferta: OfertaCorrida
        let id: Int
        let chave: String
        let primeiraVez: Date
        var saiuEm: Date?
        var cancelada = false   // "cancelou" logo depois de sair: não foi aceita
    }

    private let diario: RegistroMotor
    /// Custo por km atual (vem dos ajustes); usado no custo das corridas confirmadas.
    var custoPorKm: Double = ConfigMoto().custoPorKm

    private var abertas: [Corrida] = []
    private var ultimaOferta: OfertaVista?
    private var chavesAlheias: Set<String> = []           // ofertas lidas depois da última confirmada
    private var registradasEm: [String: (em: Date, id: Int)] = [:]   // não repetir OFERTA_DETECTADA por 20 s
    /// Ofertas aceitas durante a corrida em andamento (saíram da tela sem "cancelou"), na ordem.
    private var fila: [OfertaVista] = []

    private var classeAtual = "outra"
    private var candidata: (classe: String, tela: TelaLida, primeira: Date)?

    private let janelaDebounce: TimeInterval = 3
    private let janelaAceite: TimeInterval = 60
    private let janelaAceiteConfirmado: TimeInterval = 30
    private let janelaCancelOferta: TimeInterval = 8
    private let validadeFila: TimeInterval = 30 * 60
    private let limiteCorridaAberta: TimeInterval = 3 * 3600

    init(diario: RegistroMotor) {
        self.diario = diario
    }

    /// Oferta que faz sentido. Leituras erradas da tela de busca viram "ofertas" de R$ 8 com 1 m de viagem.
    static func plausivel(_ o: OfertaCorrida) -> Bool {
        o.valor >= 3 && o.kmViagem >= 0.3
    }

    static func chave(_ o: OfertaCorrida) -> String {
        String(format: "%.2f|%.2f|%.2f", o.valor, o.kmAtePassageiro, o.kmViagem)
    }

    // MARK: Entrada

    func observar(_ tela: TelaLida, em agora: Date = Date()) {
        encerrarVelhas(agora)
        var tela = tela
        if case .oferta(let o) = tela, !Self.plausivel(o) { tela = .outra }

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
        fila = []
    }

    /// Usuário zerou o dia: esquece o que estava em andamento.
    func esquecer() {
        abertas.removeAll()
        ultimaOferta = nil
        chavesAlheias = []
        fila = []
    }

    // MARK: Transições

    private func mudou(de anterior: String, para tela: TelaLida, em agora: Date) {
        // Oferta saindo da tela: só registra. NUNCA vira corrida nem faturamento.
        if anterior.hasPrefix("oferta:"), var ov = ultimaOferta, anterior == "oferta:" + ov.chave, ov.saiuEm == nil {
            ov.saiuEm = agora
            ultimaOferta = ov
            switch tela {
            case .aCaminho, .embarque: break   // o aceite registra
            case .oferta, .cancelada:
                // Trocou direto por outra oferta, ou veio "cancelou": não foi aceita
                evento(.ofertaSaiuDaTela, .tela, em: agora, motivo: .ofertaSaiuSemAceite, oferta: ov.oferta, ofertaId: ov.id)
            default:
                evento(.ofertaSaiuDaTela, .tela, em: agora, motivo: .ofertaSaiuSemAceite, oferta: ov.oferta, ofertaId: ov.id)
                // Com corrida em andamento, oferta que sai sem "cancelou" foi aceita pra depois.
                // Se o "cancelou" vier nos próximos segundos, sai da fila.
                if !abertas.isEmpty || !fila.isEmpty { fila.append(ov) }
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
        registradasEm = registradasEm.filter { agora.timeIntervalSince($0.value.em) < 20 }
        // Mesma oferta voltando pra tela em menos de 20 s: mesmo id, sem novo evento
        if let ja = registradasEm[chave] {
            ultimaOferta = OfertaVista(oferta: o, id: ja.id, chave: chave, primeiraVez: agora)
            chavesAlheias = []
            return
        }
        let id = diario.novoIdOferta()
        registradasEm[chave] = (agora, id)
        ultimaOferta = OfertaVista(oferta: o, id: id, chave: chave, primeiraVez: agora)
        chavesAlheias = []
        diario.contarOferta()
        var minutos = 0
        if o.minAtePassageiro != nil || o.minViagem != nil {
            minutos = (o.minAtePassageiro ?? 0) * 1000 + (o.minViagem ?? 0)
        }
        evento(.ofertaDetectada, .tela, em: agora, motivo: .lidoNaTela, oferta: o, ofertaId: id, minutos: minutos)
    }

    private func telaDeAceite(embarque: Bool, em agora: Date) {
        // Corrida já aceita e ainda sem passageiro: é a mesma (ofertas vistas na busca não trocam a corrida)
        if let i = abertas.lastIndex(where: { $0.estado == .aceita || $0.estado == .aCaminho }) {
            abertas[i].ultimaTela = agora
            if embarque && !abertas[i].chegouEmbarque {
                abertas[i].chegouEmbarque = true
                evento(.telaEmbarque, .tela, em: agora, corrida: abertas[i].id, motivo: .mesmaCorridaNaTela)
            }
            return
        }

        // A 99 só mostra o aceite da próxima depois de finalizar a atual: a que estava em andamento acabou
        let emAndamento = abertas.filter { $0.estado == .emCorrida }
        abertas.removeAll { $0.estado == .emCorrida }
        for var c in emAndamento {
            c.fim = true
            evento(.transicao, .inferencia, em: agora, corrida: c.id, de: c.estado, para: .fimDetectado,
                   motivo: .fimInferidoPorNovoAceite)
            c.estado = .fimDetectado
            encerrar(c, em: agora, porque: nil)
        }

        // Novo aceite: primeiro a oferta aceita durante a corrida anterior; senão a que acabou de sair da tela
        var ligada: OfertaVista?
        var confirmada = false
        var motivo = MotivoEvento.aceiteSemOferta
        var extra = 0
        if !fila.isEmpty {
            extra = fila.count
            ligada = fila.removeFirst()
            confirmada = extra == 1
            motivo = .ofertaAceitaDuranteCorrida
        } else if let ov = ultimaOferta, !ov.cancelada {
            let saiu = ov.saiuEm ?? agora
            let segundos = agora.timeIntervalSince(saiu)
            if segundos <= janelaAceite {
                if chavesAlheias.isEmpty {
                    ligada = ov
                    confirmada = segundos <= janelaAceiteConfirmado
                    motivo = confirmada ? .ofertaLigadaAoAceite : .ofertaLigadaFraca
                    extra = Int(segundos)
                } else {
                    motivo = .aceiteOfertaAmbigua
                }
            }
        }
        ultimaOferta = nil
        chavesAlheias = []

        let id = novaCorrida(ligada, confirmada: confirmada, motivo: motivo, extra: extra, origem: .tela, em: agora)
        if embarque, let i = abertas.lastIndex(where: { $0.id == id }) {
            abertas[i].chegouEmbarque = true
            evento(.telaEmbarque, .tela, em: agora, corrida: id, motivo: .lidoNaTela)
        }
        diario.sinal(.corridaAceita)
    }

    /// Abre uma corrida aceita (vista na tela ou inferida) e registra o aceite na linha do tempo.
    @discardableResult
    private func novaCorrida(_ ligada: OfertaVista?, confirmada: Bool, motivo: MotivoEvento, extra: Int,
                             origem: OrigemEvento, em agora: Date) -> Int {
        let id = diario.novoIdCorrida()
        var c = Corrida(id: id, estado: .aceita, criadaEm: agora, ultimaTela: agora, oferta: ligada?.oferta,
                        ofertaId: ligada?.id ?? 0, ligacaoConfirmada: confirmada, aceite: true)
        evento(.aceiteDetectado, origem, em: agora, corrida: id, para: .aceita,
               confianca: ligada == nil ? .indeterminado : (confirmada ? .confirmado : .estimado),
               motivo: motivo, extra: extra, oferta: ligada?.oferta, ofertaId: ligada?.id ?? 0)
        evento(.transicao, origem, em: agora, corrida: id, de: .aceita, para: .aCaminho,
               motivo: origem == .tela ? .lidoNaTela : .aceiteInferidoPeloFim)
        c.estado = .aCaminho
        abertas.append(c)
        return id
    }

    /// Corrida aceita durante a anterior cuja tela de aceite não foi vista: abre a partir da fila.
    private func abrirDaFila(em agora: Date) -> Bool {
        guard !fila.isEmpty else { return false }
        let n = fila.count
        let ov = fila.removeFirst()
        novaCorrida(ov, confirmada: n == 1, motivo: .aceiteInferidoPeloFim, extra: n, origem: .inferencia, em: agora)
        return true
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
        // Aceite não visto, mas havia oferta aceita durante a corrida anterior
        if abrirDaFila(em: agora) {
            passageiroABordo(em: agora)
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
            if abrirDaFila(em: agora) {
                fimDeCorrida(valorCent: valorCent, em: agora)
                return
            }
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
        // "cancelou" logo depois de uma oferta sair da tela: é a oferta (não aceita), não a sua corrida
        if let ov = ultimaOferta, let saiu = ov.saiuEm, !ov.cancelada,
           agora.timeIntervalSince(saiu) <= janelaCancelOferta {
            ultimaOferta?.cancelada = true
            fila.removeAll { $0.id == ov.id }
            evento(.cancelamentoDetectado, .tela, em: agora, motivo: .ofertaCanceladaNaTela,
                   oferta: ov.oferta, ofertaId: ov.id)
            return
        }
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
        fila.removeAll { agora.timeIntervalSince($0.saiuEm ?? $0.primeiraVez) > validadeFila }
        guard !velhas.isEmpty else { return }
        abertas.removeAll { agora.timeIntervalSince($0.criadaEm) > limiteCorridaAberta }
        for c in velhas { encerrar(c, em: agora, porque: .tempoEsgotado) }
    }

    // MARK: Decisão final

    /// Classifica pela evidência e só aí mexe em dinheiro. `porque` = motivo de fechar sem tela de fim.
    private func encerrar(_ c: Corrida, em agora: Date, porque: MotivoEvento?) {
        let valorCent = c.valorFinalCent ?? c.oferta.map { Int(($0.valor * 100).rounded()) }
        // Valor confirmado = lido na tela de fim, ou oferta ligada ao aceite com associação confirmada
        let valorConfirmado = c.valorFinalCent != nil || (c.oferta != nil && c.ligacaoConfirmada)

        var falta = 0
        if !c.aceite { falta |= Falta.aceite }
        if valorCent == nil { falta |= Falta.valor }
        else if !valorConfirmado { falta |= Falta.ligacao }
        if !c.aBordo && !c.fim { falta |= Falta.aBordo }   // tela de fim implica passageiro a bordo
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
               confianca: confianca, motivo: motivo, extra: falta, oferta: c.oferta, ofertaId: c.ofertaId)

        switch final {
        case .confirmada:
            let km = c.oferta.map { $0.kmAtePassageiro + $0.kmViagem } ?? 0
            diario.somarConfirmada(valorCent: valorCent ?? 0,
                                   custoCent: Int((km * custoPorKm * 100).rounded()),
                                   metros: Int((km * 1000).rounded()))
            evento(.faturamentoConfirmado, .inferencia, em: agora, corrida: c.id, confianca: .confirmado,
                   motivo: .evidenciaCompleta, valorCent: valorCent ?? 0)
            diario.sinal(.corridaFeita)
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
                        oferta: OfertaCorrida? = nil, ofertaId: Int = 0, minutos: Int = 0, valorCent: Int = 0) {
        var e = EventoLinha(seq: 0, em: agora, tipo: tipo, origem: origem)
        e.oferta = ofertaId
        e.minutos = minutos
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
