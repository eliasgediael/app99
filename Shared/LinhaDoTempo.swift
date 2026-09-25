import Foundation

// MARK: - Estados e confiança

/// Estado de uma corrida. Cada mudança vira um evento na linha do tempo.
enum EstadoCorrida: Int, Codable {
    case aceita = 1
    case aCaminho = 2
    case passageiroABordo = 3
    case emCorrida = 4
    case fimDetectado = 5
    case confirmada = 6
    case estimada = 7
    case indeterminada = 8
    case cancelada = 9

    var nome: String {
        switch self {
        case .aceita:           return "ACEITA"
        case .aCaminho:         return "A_CAMINHO"
        case .passageiroABordo: return "PASSAGEIRO_A_BORDO"
        case .emCorrida:        return "EM_CORRIDA"
        case .fimDetectado:     return "FIM_DE_CORRIDA_DETECTADO"
        case .confirmada:       return "CONFIRMADA"
        case .estimada:         return "ESTIMADA"
        case .indeterminada:    return "INDETERMINADA"
        case .cancelada:        return "CANCELADA"
        }
    }

    var encerrada: Bool { [.confirmada, .estimada, .indeterminada, .cancelada].contains(self) }
}

/// Só CONFIRMADO entra no faturamento principal.
enum Confianca: Int, Codable {
    case confirmado = 1
    case estimado = 2
    case indeterminado = 3

    var nome: String {
        switch self {
        case .confirmado:    return "CONFIRMADO"
        case .estimado:      return "ESTIMADO"
        case .indeterminado: return "INDETERMINADO"
        }
    }
}

// MARK: - Evento

enum TipoEvento: Int, Codable {
    case leituraIniciada = 1
    case leituraEncerrada = 2
    case ofertaDetectada = 3
    case ofertaSaiuDaTela = 4
    case aceiteDetectado = 5
    case telaEmbarque = 6          // "Iniciar corrida": chegou no local, esperando o passageiro
    case passageiroABordo = 7
    case fimDetectado = 8
    case cancelamentoDetectado = 9
    case transicao = 10            // mudança de estado de uma corrida
    case faturamentoConfirmado = 11
    case faturamentoEstimado = 12
    case semFaturamento = 13
    case diaZerado = 14

    var nome: String {
        switch self {
        case .leituraIniciada:       return "LEITURA_INICIADA"
        case .leituraEncerrada:      return "LEITURA_ENCERRADA"
        case .ofertaDetectada:       return "OFERTA_DETECTADA"
        case .ofertaSaiuDaTela:      return "OFERTA_SAIU_DA_TELA"
        case .aceiteDetectado:       return "ACEITE_DETECTADO"
        case .telaEmbarque:          return "CHEGOU_NO_EMBARQUE"
        case .passageiroABordo:      return "PASSAGEIRO_A_BORDO"
        case .fimDetectado:          return "FIM_DE_CORRIDA_DETECTADO"
        case .cancelamentoDetectado: return "CANCELAMENTO_DETECTADO"
        case .transicao:             return "ESTADO"
        case .faturamentoConfirmado: return "FATURAMENTO_CONFIRMADO"
        case .faturamentoEstimado:   return "FATURAMENTO_ESTIMADO"
        case .semFaturamento:        return "SEM_FATURAMENTO"
        case .diaZerado:             return "DIA_ZERADO"
        }
    }
}

enum OrigemEvento: Int, Codable {
    case tela = 1          // lido na tela
    case inferencia = 2    // deduzido de outros eventos
    case sistema = 3       // leitura ligou/desligou, usuário zerou etc.

    var nome: String {
        switch self {
        case .tela:       return "tela"
        case .inferencia: return "inferência"
        case .sistema:    return "sistema"
        }
    }
}

/// Por que o motor tomou a decisão. `extra` complementa alguns motivos.
enum MotivoEvento: Int, Codable {
    case nenhum = 0
    case lidoNaTela = 1
    case ofertaLigadaAoAceite = 2      // extra = segundos entre a oferta sair da tela e o aceite
    case aceiteSemOferta = 3           // nenhuma oferta nos últimos 60 s
    case aceiteOfertaAmbigua = 4       // outra oferta apareceu no meio
    case aBordoImplicaEmCorrida = 5
    case aBordoSemAceite = 6
    case fimSemCorridaAberta = 7
    case evidenciaCompleta = 8
    case evidenciaIncompleta = 9       // extra = máscara do que faltou (ver Falta)
    case substituidaPorNovoAceite = 10
    case canceladaNaTela = 11
    case ofertaSaiuSemAceite = 12
    case valorFinalLidoNaTela = 13
    case tempoEsgotado = 14            // corrida aberta há mais de 3 h
    case leituraEncerrada = 15
    case zeradoPeloUsuario = 16
    case cancelamentoSemCorrida = 17
    case mesmaCorridaNaTela = 18

    func texto(extra: Int) -> String {
        switch self {
        case .nenhum:                   return ""
        case .lidoNaTela:               return "Lido na tela."
        case .ofertaLigadaAoAceite:     return "Aceite veio \(extra) s depois desta oferta sair da tela, sem outra oferta no meio."
        case .aceiteSemOferta:          return "Nenhuma oferta nos 60 s antes do aceite: valor desconhecido."
        case .aceiteOfertaAmbigua:      return "Outra oferta apareceu no meio: não dá pra saber qual foi aceita. Valor desconhecido."
        case .aBordoImplicaEmCorrida:   return "Inferido: passageiro a bordo ⇒ corrida em andamento."
        case .aBordoSemAceite:          return "Passageiro a bordo sem aceite detectado antes."
        case .fimSemCorridaAberta:      return "Tela de fim sem corrida aberta: ignorada."
        case .evidenciaCompleta:        return "Aceite + valor + passageiro a bordo + fim detectados."
        case .evidenciaIncompleta:      return "Faltou: " + Falta.descrever(extra) + "."
        case .substituidaPorNovoAceite: return "Novo aceite antes do passageiro embarcar nesta."
        case .canceladaNaTela:          return "Cancelamento lido na tela."
        case .ofertaSaiuSemAceite:      return "Oferta saiu da tela. Sem aceite, não fatura."
        case .valorFinalLidoNaTela:     return "Valor final lido na tela de fim."
        case .tempoEsgotado:            return "Corrida aberta há mais de 3 h: encerrada com o que se sabe."
        case .leituraEncerrada:         return "Leitura desligada com a corrida aberta: encerrada com o que se sabe."
        case .zeradoPeloUsuario:        return "Números de hoje apagados pelo usuário."
        case .cancelamentoSemCorrida:   return "Cancelamento sem corrida aceita aberta."
        case .mesmaCorridaNaTela:       return "Tela da corrida que já estava aberta."
        }
    }
}

/// Evidências que podem faltar pra confirmar uma corrida (máscara de bits).
enum Falta {
    static let aceite = 1, valor = 2, aBordo = 4, fim = 8

    static func descrever(_ mascara: Int) -> String {
        var partes: [String] = []
        if mascara & aceite != 0 { partes.append("aceite") }
        if mascara & valor != 0 { partes.append("valor (oferta ligada)") }
        if mascara & aBordo != 0 { partes.append("passageiro a bordo") }
        if mascara & fim != 0 { partes.append("tela de fim") }
        return partes.isEmpty ? "nada" : partes.joined(separator: ", ")
    }
}

/// Um evento da linha do tempo. Só números, pra caber no CanalDarwin.
struct EventoLinha: Codable, Equatable {
    var seq: Int
    var em: Int                          // segundos desde 1970
    var tipo: TipoEvento
    var origem: OrigemEvento
    var corrida: Int = 0                 // id da corrida (0 = nenhuma)
    var estadoAnterior: EstadoCorrida?
    var estadoNovo: EstadoCorrida?
    var confianca: Confianca?
    var motivo: MotivoEvento = .nenhum
    var extra: Int = 0
    var valorCent: Int = 0
    var buscaM: Int = 0
    var viagemM: Int = 0
    var nota100: Int = 0

    var data: Date { Date(timeIntervalSince1970: TimeInterval(em)) }
    var dia: Int { DiaRelatorio.numero(de: data) }

    // MARK: Transporte (extensão → app)

    static let canal = CanalDarwin(prefixo: "com.elias.app99.tl", campos: 14)
    /// App → extensão: "manda os eventos depois deste seq" (1 campo)
    static let canalPedido = CanalDarwin(prefixo: "com.elias.app99.tlp", campos: 1)

    var campos: [Int] {
        [seq, em, tipo.rawValue, origem.rawValue, corrida,
         estadoAnterior?.rawValue ?? 0, estadoNovo?.rawValue ?? 0, confianca?.rawValue ?? 0,
         motivo.rawValue, extra, valorCent, buscaM, viagemM, nota100]
    }

    init(seq: Int, em: Date, tipo: TipoEvento, origem: OrigemEvento) {
        self.seq = seq
        self.em = Int(em.timeIntervalSince1970)
        self.tipo = tipo
        self.origem = origem
    }

    init?(campos c: [Int]) {
        guard c.count == 14, let tipo = TipoEvento(rawValue: c[2]), let origem = OrigemEvento(rawValue: c[3]) else { return nil }
        seq = c[0]; em = c[1]; self.tipo = tipo; self.origem = origem; corrida = c[4]
        estadoAnterior = EstadoCorrida(rawValue: c[5])
        estadoNovo = EstadoCorrida(rawValue: c[6])
        confianca = Confianca(rawValue: c[7])
        motivo = MotivoEvento(rawValue: c[8]) ?? .nenhum
        extra = c[9]; valorCent = c[10]; buscaM = c[11]; viagemM = c[12]; nota100 = c[13]
    }
}
