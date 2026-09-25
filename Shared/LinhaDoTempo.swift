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
    // Gerados pelo app (não pela leitura da tela)
    case turnoIniciado = 15
    case turnoPausado = 16
    case turnoRetomado = 17
    case turnoEncerrado = 18
    case custoRegistrado = 19
    case gpsSemSinal = 20
    case gpsRetomado = 21

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
        case .turnoIniciado:         return "TURNO_INICIADO"
        case .turnoPausado:          return "TURNO_PAUSADO"
        case .turnoRetomado:         return "TURNO_RETOMADO"
        case .turnoEncerrado:        return "TURNO_ENCERRADO"
        case .custoRegistrado:       return "CUSTO_REGISTRADO"
        case .gpsSemSinal:           return "GPS_SEM_SINAL"
        case .gpsRetomado:           return "GPS_RETOMADO"
        }
    }
}

enum OrigemEvento: Int, Codable {
    case tela = 1          // lido na tela
    case inferencia = 2    // deduzido de outros eventos
    case sistema = 3       // leitura ligou/desligou etc.
    case usuario = 4       // registrado à mão (turno, abastecimento, custo)
    case gps = 5

    var nome: String {
        switch self {
        case .tela:       return "tela"
        case .inferencia: return "inferência"
        case .sistema:    return "sistema"
        case .usuario:    return "você"
        case .gps:        return "GPS"
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
    case ofertaLigadaFraca = 19         // extra = segundos (10 a 60 s): associação só ESTIMADA
    case registradoPeloUsuario = 20

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
        case .ofertaLigadaFraca:        return "Aceite veio \(extra) s depois desta oferta sair da tela: associação só ESTIMADA (confirmada é até 10 s)."
        case .registradoPeloUsuario:    return "Registrado por você."
        }
    }
}

/// Evidências que podem faltar pra confirmar uma corrida (máscara de bits).
enum Falta {
    static let aceite = 1, valor = 2, aBordo = 4, fim = 8
    static let ligacao = 16   // oferta↔aceite só ESTIMADA

    static func descrever(_ mascara: Int) -> String {
        var partes: [String] = []
        if mascara & aceite != 0 { partes.append("aceite") }
        if mascara & valor != 0 { partes.append("valor (oferta ligada)") }
        if mascara & aBordo != 0 { partes.append("passageiro a bordo") }
        if mascara & fim != 0 { partes.append("tela de fim") }
        if mascara & ligacao != 0 { partes.append("associação confirmada oferta↔aceite") }
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
    /// Id da oferta (OFERTA_DETECTADA, OFERTA_SAIU_DA_TELA, ACEITE_DETECTADO quando ligada). 0 = nenhuma.
    var oferta: Int = 0
    /// Minutos da oferta: busca × 1000 + viagem (só em OFERTA_DETECTADA; 0 = não lido).
    var minutos: Int = 0

    // Preenchidos só no app (não viajam pelo canal): contexto do GPS e texto de eventos do app.
    var lat: Double?
    var lon: Double?
    var precisaoM: Double?
    var kmTurno: Double?          // km acumulado do turno no momento do evento
    var texto: String?            // ex.: "Abastecimento · R$ 20,00 · 3,18 L"
    var ref: String?              // id do registro relacionado (ex.: custo)

    var data: Date { Date(timeIntervalSince1970: TimeInterval(em)) }
    var dia: Int { DiaRelatorio.numero(de: data) }

    // MARK: Transporte (extensão → app)

    static let canal = CanalDarwin(prefixo: "com.elias.app99.tl2", campos: 16)
    /// App → extensão: "manda os eventos depois deste seq" (1 campo)
    static let canalPedido = CanalDarwin(prefixo: "com.elias.app99.tlp2", campos: 1)

    var campos: [Int] {
        [seq, em, tipo.rawValue, origem.rawValue, corrida,
         estadoAnterior?.rawValue ?? 0, estadoNovo?.rawValue ?? 0, confianca?.rawValue ?? 0,
         motivo.rawValue, extra, valorCent, buscaM, viagemM, nota100, oferta, minutos]
    }

    /// Eventos criados no app usam seq negativo (não se misturam com os da extensão).
    var doApp: Bool { seq < 0 }

    // Lê também eventos salvos antes dos campos novos (o que falta = padrão)
    private enum CodingKeys: String, CodingKey {
        case seq, em, tipo, origem, corrida, estadoAnterior, estadoNovo, confianca, motivo, extra
        case valorCent, buscaM, viagemM, nota100, oferta, minutos
        case lat, lon, precisaoM, kmTurno, texto, ref
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        em = try c.decode(Int.self, forKey: .em)
        tipo = try c.decode(TipoEvento.self, forKey: .tipo)
        origem = try c.decode(OrigemEvento.self, forKey: .origem)
        corrida = try c.decodeIfPresent(Int.self, forKey: .corrida) ?? 0
        estadoAnterior = try c.decodeIfPresent(EstadoCorrida.self, forKey: .estadoAnterior)
        estadoNovo = try c.decodeIfPresent(EstadoCorrida.self, forKey: .estadoNovo)
        confianca = try c.decodeIfPresent(Confianca.self, forKey: .confianca)
        motivo = try c.decodeIfPresent(MotivoEvento.self, forKey: .motivo) ?? .nenhum
        extra = try c.decodeIfPresent(Int.self, forKey: .extra) ?? 0
        valorCent = try c.decodeIfPresent(Int.self, forKey: .valorCent) ?? 0
        buscaM = try c.decodeIfPresent(Int.self, forKey: .buscaM) ?? 0
        viagemM = try c.decodeIfPresent(Int.self, forKey: .viagemM) ?? 0
        nota100 = try c.decodeIfPresent(Int.self, forKey: .nota100) ?? 0
        oferta = try c.decodeIfPresent(Int.self, forKey: .oferta) ?? 0
        minutos = try c.decodeIfPresent(Int.self, forKey: .minutos) ?? 0
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try c.decodeIfPresent(Double.self, forKey: .lon)
        precisaoM = try c.decodeIfPresent(Double.self, forKey: .precisaoM)
        kmTurno = try c.decodeIfPresent(Double.self, forKey: .kmTurno)
        texto = try c.decodeIfPresent(String.self, forKey: .texto)
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
    }

    init(seq: Int, em: Date, tipo: TipoEvento, origem: OrigemEvento) {
        self.seq = seq
        self.em = Int(em.timeIntervalSince1970)
        self.tipo = tipo
        self.origem = origem
    }

    init?(campos c: [Int]) {
        guard c.count == 16, let tipo = TipoEvento(rawValue: c[2]), let origem = OrigemEvento(rawValue: c[3]) else { return nil }
        seq = c[0]; em = c[1]; self.tipo = tipo; self.origem = origem; corrida = c[4]
        estadoAnterior = EstadoCorrida(rawValue: c[5])
        estadoNovo = EstadoCorrida(rawValue: c[6])
        confianca = Confianca(rawValue: c[7])
        motivo = MotivoEvento(rawValue: c[8]) ?? .nenhum
        extra = c[9]; valorCent = c[10]; buscaM = c[11]; viagemM = c[12]; nota100 = c[13]
        oferta = c[14]; minutos = c[15]
    }
}
