import Foundation

// Tudo aqui é CALCULADO a partir de: eventos da linha do tempo + custos + pontos de GPS + ajustes.
// Nada é guardado em dobro: se a regra mudar, o cálculo muda junto pra todos os turnos.

// MARK: - Corridas e ofertas (derivadas dos eventos)

struct CorridaAnalisada: Identifiable {
    let id: Int
    var ofertaId: Int?
    var ligacao: Confianca = .indeterminado      // associação oferta ↔ aceite
    var aceiteEm: Date?
    var aBordoEm: Date?
    var fimEm: Date?                             // só se a tela de fim foi vista
    var encerradaEm: Date?
    var estado: EstadoCorrida?
    var confianca: Confianca?                    // nil = ainda aberta
    var motivo: MotivoEvento = .nenhum
    var falta = 0
    var valorOfertaCent: Int?
    var valorFinalCent: Int?                     // só se lido na tela de fim
    var buscaM: Int?
    var viagemM: Int?
    var nota: Double?
    var origem: Coordenada?                      // GPS no "passageiro a bordo" (nunca inventado)
    var destino: Coordenada?                     // GPS na tela de fim (só se ela foi vista)
    var kmGPS = Medida.indeterminada(.gps, "sem GPS")
    var duracao = Medida.indeterminada(.tela, "sem a bordo + fim")

    /// Valor com a confiança da corrida: só CONFIRMADA entra no faturamento principal.
    var valor: Medida {
        guard let cent = valorFinalCent ?? valorOfertaCent else { return .indeterminada(.tela, "valor desconhecido") }
        switch confianca {
        case .confirmado?: return Medida(valor: Double(cent) / 100, confianca: .confirmado, fonte: .tela)
        case .estimado?:   return Medida(valor: Double(cent) / 100, confianca: .estimado, fonte: .tela,
                                         nota: "faltou: " + Falta.descrever(falta))
        default:           return .indeterminada(.tela, "corrida não confirmada")
        }
    }
    var porKm: Medida { Medida.dividir(valor, kmGPS, nota: "R$/km pelo GPS da corrida") }
    var porHora: Medida { Medida.dividir(valor, duracao, fator: 3600, nota: "R$/h a bordo → fim") }
    var regiaoOrigem: String? { origem?.regiao }
    var regiaoDestino: String? { destino?.regiao }
}

enum ResultadoOferta {
    case aceita          // ligada a um aceite (ver `associacao`)
    case naoAceita       // recusada OU expirou: a tela não permite distinguir
    case emAberto        // ainda pode ser aceita
}

struct OfertaAnalisada: Identifiable {
    let id: Int
    let em: Date
    var valorCent: Int
    var buscaM: Int
    var viagemM: Int
    var minBusca: Int?
    var minViagem: Int?
    var nota: Double?
    var local: Coordenada?
    var resultado: ResultadoOferta = .emAberto
    var corridaId: Int?
    var associacao: Confianca?

    var km: Double { Double(buscaM + viagemM) / 1000 }
    var porKm: Double? { km > 0 ? Double(valorCent) / 100 / km : nil }
}

// MARK: - Estado do motorista no tempo

enum EstadoMotorista: String, CaseIterable {
    case aguardando      // leitura ligada, nenhuma corrida aberta
    case aCaminho        // aceitou, indo buscar
    case emCorrida       // passageiro a bordo
    case pausado         // pausa manual
    case semLeitura      // leitura desligada/sem dados: INDETERMINADO

    var nome: String {
        switch self {
        case .aguardando: return "Aguardando"
        case .aCaminho:   return "Indo buscar"
        case .emCorrida:  return "Em corrida"
        case .pausado:    return "Pausado"
        case .semLeitura: return "Sem leitura"
        }
    }
}

struct SegmentoEstado {
    var inicio: Date
    var fim: Date
    var estado: EstadoMotorista
    var duracao: TimeInterval { fim.timeIntervalSince(inicio) }
}

// MARK: - Trajeto (GPS filtrado)

struct Trecho {
    var de: PontoGPS
    var para: PontoGPS
    var metros: Double
    var meio: Date { de.em.addingTimeInterval(para.em.timeIntervalSince(de.em) / 2) }
}

struct Trajeto {
    var trechos: [Trecho] = []
    /// Períodos sem sinal (> 2 min sem ponto válido): NÃO são ligados em linha reta.
    var buracos: [Intervalo] = []
    var metros: Double { trechos.reduce(0) { $0 + $1.metros } }

    static let precisaoMaxima = 50.0          // m
    static let buracoAPartirDe: TimeInterval = 120
    static let velocidadeMaxima = 150 / 3.6   // m/s (moto) — acima disso é salto do GPS

    /// Filtros: precisão ruim, tremida parada (< precisão), salto impossível, duplicado, buraco de sinal.
    static func calcular(_ pontos: [PontoGPS]) -> Trajeto {
        var t = Trajeto()
        var ancora: PontoGPS?
        var ultimoValido: Date?
        for p in pontos.sorted(by: { $0.em < $1.em }) {
            guard p.precisaoM > 0, p.precisaoM <= precisaoMaxima else { continue }
            if let u = ultimoValido, p.em <= u { continue }                       // duplicado
            if let u = ultimoValido, p.em.timeIntervalSince(u) > buracoAPartirDe {
                t.buracos.append(Intervalo(inicio: u, fim: p.em))
                ancora = p; ultimoValido = p.em
                continue
            }
            ultimoValido = p.em
            guard let a = ancora else { ancora = p; continue }
            let d = a.coord.distancia(ate: p.coord)
            if d < max(p.precisaoM, a.precisaoM, 10) { continue }                // tremida parado
            let dt = p.em.timeIntervalSince(a.em)
            if dt <= 0 || d / dt > velocidadeMaxima { continue }                 // salto impossível
            t.trechos.append(Trecho(de: a, para: p, metros: d))
            ancora = p
        }
        return t
    }
}

// MARK: - Resumo do turno

struct ResumoTurno {
    let turno: Turno
    var corridas: [CorridaAnalisada] = []
    var ofertas: [OfertaAnalisada] = []
    var custos: [Custo] = []
    var segmentos: [SegmentoEstado] = []
    var trajeto = Trajeto()
    var temGPS = false

    // Tempo
    var duracao = Medida(valor: 0, confianca: .confirmado, fonte: .relogio)
    var tempoPorEstado: [EstadoMotorista: TimeInterval] = [:]
    var tempoParado = Medida.indeterminada(.gps, "sem GPS")
    var tempoSemSinalGPS: TimeInterval = 0

    // Distância
    var km = Medida.indeterminada(.gps, "sem GPS")
    var kmPorEstado: [EstadoMotorista: Double] = [:]

    // Financeiro
    var faturamentoConfirmado = Medida(valor: 0, confianca: .confirmado, fonte: .tela)
    var faturamentoEstimado = Medida(valor: 0, confianca: .estimado, fonte: .tela)
    var combustivel = Medida(valor: 0, confianca: .confirmado, fonte: .usuario,
                             nota: "abastecido no turno (não é o consumido)")
    var outrosCustos = Medida(valor: 0, confianca: .confirmado, fonte: .usuario)
    var custoEstimadoPorKm = Medida.indeterminada(.configuracao, "sem GPS")

    var tempoAtivo: Medida {
        Medida(valor: (duracao.valor ?? 0) - (tempoPorEstado[.pausado] ?? 0), confianca: .confirmado, fonte: .relogio,
               nota: "duração − pausas")
    }
    /// Faturamento confirmado − custos registrados à mão.
    var resultado: Medida {
        var r = Medida.subtrair(faturamentoConfirmado,
                                Medida(valor: (combustivel.valor ?? 0) + (outrosCustos.valor ?? 0),
                                       confianca: .confirmado, fonte: .usuario),
                                nota: "confirmado − custos registrados")
        r.confianca = .estimado   // abastecimento ≠ combustível gasto no turno
        return r
    }
    /// Faturamento confirmado − custo/km dos Ajustes × km do GPS − outros custos.
    var resultadoEstimado: Medida {
        Medida.subtrair(Medida.subtrair(faturamentoConfirmado, custoEstimadoPorKm), outrosCustos,
                        nota: "confirmado − custo/km × km − outros")
    }
    var porKm: Medida { Medida.dividir(faturamentoConfirmado, km, nota: "confirmado ÷ km do GPS") }
    var porHora: Medida { Medida.dividir(faturamentoConfirmado, duracao, fator: 3600, nota: "confirmado ÷ duração") }
    var porHoraAtivo: Medida { Medida.dividir(faturamentoConfirmado, tempoAtivo, fator: 3600, nota: "confirmado ÷ tempo sem pausa") }
    var mediaPorCorrida: Medida {
        Medida.dividir(faturamentoConfirmado,
                       Medida(valor: Double(corridas.filter { $0.confianca == .confirmado }.count),
                              confianca: .confirmado, fonte: .calculo),
                       nota: "por corrida confirmada")
    }
    var combustivelPorKm: Medida {
        var m = Medida.dividir(combustivel, km, nota: "abastecido ÷ km (fica preciso em vários turnos)")
        if m.valor != nil { m.confianca = .estimado }
        return m
    }
    func percentual(_ e: EstadoMotorista) -> Double? {
        guard let d = duracao.valor, d > 0 else { return nil }
        return (tempoPorEstado[e] ?? 0) / d
    }

    var corridasConfirmadas: Int { corridas.filter { $0.confianca == .confirmado }.count }
    var corridasEstimadas: Int { corridas.filter { $0.confianca == .estimado }.count }
    var corridasIndeterminadas: Int { corridas.filter { $0.confianca == .indeterminado }.count }
}

enum AnaliseTurno {

    /// `eventos`: todos os que o app tem (o turno pega os do seu horário).
    static func calcular(_ turno: Turno, eventos todos: [EventoLinha], custos todosCustos: [Custo],
                         pontos: [PontoGPS], custoPorKm: Double, agora: Date = Date()) -> ResumoTurno {
        var r = ResumoTurno(turno: turno)
        let fim = turno.fim ?? agora
        let eventos = todos.filter { turno.contem($0.data) }.sorted { ($0.em, $0.seq) < ($1.em, $1.seq) }

        r.duracao = Medida(valor: fim.timeIntervalSince(turno.inicio), confianca: .confirmado, fonte: .relogio)
        r.custos = todosCustos.filter { $0.turno == turno.id || ($0.turno == nil && turno.contem($0.em)) }
        r.combustivel.valor = r.custos.filter { $0.tipo == .combustivel }.reduce(0) { $0 + $1.valor }
        r.outrosCustos.valor = r.custos.filter { $0.tipo != .combustivel }.reduce(0) { $0 + $1.valor }

        r.trajeto = Trajeto.calcular(pontos.filter { turno.contem($0.em) })
        r.temGPS = !pontos.isEmpty
        r.corridas = corridas(eventos, trajeto: r.trajeto, temGPS: r.temGPS)
        r.ofertas = ofertas(eventos, corridas: r.corridas, turnoAcabou: turno.fim != nil, agora: agora)
        r.segmentos = segmentos(turno, todos: todos, ate: fim)

        for s in r.segmentos { r.tempoPorEstado[s.estado, default: 0] += s.duracao }

        let confirmadas = r.corridas.compactMap { $0.confianca == .confirmado ? $0.valor.valor : nil }
        let estimadas = r.corridas.compactMap { $0.confianca == .estimado ? $0.valor.valor : nil }
        r.faturamentoConfirmado.valor = confirmadas.reduce(0, +)
        r.faturamentoEstimado.valor = estimadas.reduce(0, +)

        if r.temGPS {
            let metros = r.trajeto.metros
            r.km = Medida(valor: metros / 1000, confianca: r.trajeto.buracos.isEmpty ? .confirmado : .estimado,
                          fonte: .gps, nota: r.trajeto.buracos.isEmpty ? nil : "houve períodos sem sinal (não somados)")
            r.tempoSemSinalGPS = r.trajeto.buracos.reduce(0) { $0 + $1.duracao() }
            for t in r.trajeto.trechos {
                let estado = r.segmentos.first { $0.inicio <= t.meio && t.meio < $0.fim }?.estado ?? .semLeitura
                r.kmPorEstado[estado, default: 0] += t.metros / 1000
            }
            let emMovimento = r.trajeto.trechos.reduce(0.0) { $0 + $1.para.em.timeIntervalSince($1.de.em) }
            r.tempoParado = Medida(valor: max(0, (r.duracao.valor ?? 0) - emMovimento - r.tempoSemSinalGPS),
                                   confianca: .estimado, fonte: .gps, nota: "tempo sem deslocamento no GPS")
            r.custoEstimadoPorKm = Medida(valor: metros / 1000 * custoPorKm, confianca: .estimado, fonte: .configuracao,
                                          nota: "km do GPS × custo/km dos Ajustes")
        }
        return r
    }

    // MARK: Corridas

    static func corridas(_ eventos: [EventoLinha], trajeto: Trajeto, temGPS: Bool) -> [CorridaAnalisada] {
        var porId: [Int: CorridaAnalisada] = [:]
        for e in eventos where e.corrida > 0 {
            var c = porId[e.corrida] ?? CorridaAnalisada(id: e.corrida)
            let local = e.lat.flatMap { lat in e.lon.map { Coordenada(lat: lat, lon: $0) } }
            switch e.tipo {
            case .aceiteDetectado:
                c.aceiteEm = e.data
                c.ligacao = e.confianca ?? .indeterminado
                if e.oferta > 0 {
                    c.ofertaId = e.oferta
                    c.valorOfertaCent = e.valorCent
                    c.buscaM = e.buscaM
                    c.viagemM = e.viagemM
                    c.nota = e.nota100 > 0 ? Double(e.nota100) / 100 : nil
                }
            case .passageiroABordo:
                c.aBordoEm = e.data
                c.origem = local
            case .fimDetectado:
                c.fimEm = e.data
                c.destino = local
                if e.motivo == .valorFinalLidoNaTela, e.valorCent > 0 { c.valorFinalCent = e.valorCent }
            case .transicao:
                c.estado = e.estadoNovo
                if e.estadoNovo?.encerrada == true {
                    c.encerradaEm = e.data
                    c.confianca = e.confianca ?? (e.estadoNovo == .cancelada ? .indeterminado : nil)
                    c.motivo = e.motivo
                    c.falta = e.extra
                }
            default: break
            }
            porId[e.corrida] = c
        }

        return porId.values.sorted { $0.id < $1.id }.map { c in
            var c = c
            if let a = c.aBordoEm, let f = c.fimEm {
                c.duracao = Medida(valor: f.timeIntervalSince(a), confianca: .confirmado, fonte: .tela)
            }
            if temGPS, let a = c.aBordoEm, let f = c.fimEm ?? c.encerradaEm {
                let trechos = trajeto.trechos.filter { $0.meio >= a && $0.meio <= f }
                let comBuraco = trajeto.buracos.contains { $0.inicio < f && ($0.fim ?? f) > a }
                c.kmGPS = Medida(valor: trechos.reduce(0) { $0 + $1.metros } / 1000,
                                 confianca: (comBuraco || c.fimEm == nil) ? .estimado : .confirmado, fonte: .gps,
                                 nota: comBuraco ? "sem sinal em parte da corrida" : (c.fimEm == nil ? "fim não visto" : nil))
            }
            return c
        }
    }

    // MARK: Ofertas

    static func ofertas(_ eventos: [EventoLinha], corridas: [CorridaAnalisada],
                        turnoAcabou: Bool, agora: Date) -> [OfertaAnalisada] {
        var lista: [OfertaAnalisada] = []
        for e in eventos where e.tipo == .ofertaDetectada && e.oferta > 0 {
            var o = OfertaAnalisada(id: e.oferta, em: e.data, valorCent: e.valorCent, buscaM: e.buscaM, viagemM: e.viagemM)
            if e.minutos > 0 { o.minBusca = e.minutos / 1000; o.minViagem = e.minutos % 1000 }
            o.nota = e.nota100 > 0 ? Double(e.nota100) / 100 : nil
            o.local = e.lat.flatMap { lat in e.lon.map { Coordenada(lat: lat, lon: $0) } }
            if let c = corridas.first(where: { $0.ofertaId == e.oferta }) {
                o.resultado = .aceita
                o.corridaId = c.id
                o.associacao = c.ligacao
            } else if turnoAcabou || agora.timeIntervalSince(e.data) > 120 {
                o.resultado = .naoAceita
            }
            lista.append(o)
        }
        return lista
    }

    // MARK: Segmentos de estado

    static func segmentos(_ turno: Turno, todos: [EventoLinha], ate fim: Date) -> [SegmentoEstado] {
        let ordenados = todos.sorted { ($0.em, $0.seq) < ($1.em, $1.seq) }
        // Leitura já estava ligada quando o turno começou?
        let antes = ordenados.last { $0.data < turno.inicio && ($0.tipo == .leituraIniciada || $0.tipo == .leituraEncerrada) }
        var leitura = antes?.tipo == .leituraIniciada
        var indoBuscar: Set<Int> = []
        var emCorrida: Set<Int> = []

        // Marcos: eventos do turno + bordas das pausas
        var marcos: [(Date, EventoLinha?)] = ordenados.filter { turno.contem($0.data) && $0.data <= fim }.map { ($0.data, $0) }
        for p in turno.pausas {
            marcos.append((p.inicio, nil))
            if let f = p.fim { marcos.append((f, nil)) }
        }
        marcos.sort { $0.0 < $1.0 }

        func estado(em t: Date) -> EstadoMotorista {
            if turno.pausas.contains(where: { $0.inicio <= t && t < ($0.fim ?? .distantFuture) }) { return .pausado }
            if !leitura { return .semLeitura }
            if !emCorrida.isEmpty { return .emCorrida }
            if !indoBuscar.isEmpty { return .aCaminho }
            return .aguardando
        }

        var segs: [SegmentoEstado] = []
        var cursor = turno.inicio
        func fechar(ate t: Date) {
            guard t > cursor else { return }
            let e = estado(em: cursor)
            if let u = segs.last, u.estado == e, u.fim == cursor { segs[segs.count - 1].fim = t }
            else { segs.append(SegmentoEstado(inicio: cursor, fim: t, estado: e)) }
            cursor = t
        }

        for (t, e) in marcos {
            fechar(ate: t)
            guard let e else { continue }
            switch e.tipo {
            case .leituraIniciada:  leitura = true
            case .leituraEncerrada: leitura = false; indoBuscar.removeAll(); emCorrida.removeAll()
            case .aceiteDetectado:  indoBuscar.insert(e.corrida)
            case .passageiroABordo: indoBuscar.remove(e.corrida); emCorrida.insert(e.corrida)
            case .transicao where e.estadoNovo?.encerrada == true:
                indoBuscar.remove(e.corrida); emCorrida.remove(e.corrida)
            default: break
            }
        }
        fechar(ate: fim)
        return segs
    }
}

// MARK: - Histórico (base pras comparações futuras)

enum Periodo: CaseIterable {
    case hoje, ontem, ultimos7, ultimos30, semana, mes

    func intervalo(agora: Date = Date(), calendario: Calendar = .current) -> DateInterval {
        let hoje = calendario.startOfDay(for: agora)
        func dias(_ n: Int) -> Date { calendario.date(byAdding: .day, value: n, to: hoje)! }
        switch self {
        case .hoje:      return DateInterval(start: hoje, end: agora)
        case .ontem:     return DateInterval(start: dias(-1), end: hoje)
        case .ultimos7:  return DateInterval(start: dias(-6), end: agora)
        case .ultimos30: return DateInterval(start: dias(-29), end: agora)
        case .semana:    return calendario.dateInterval(of: .weekOfYear, for: agora) ?? DateInterval(start: hoje, end: agora)
        case .mes:       return calendario.dateInterval(of: .month, for: agora) ?? DateInterval(start: hoje, end: agora)
        }
    }
}

/// Chaves de agrupamento. Tudo sai só dos seus dados; grupo com poucos dados deve ser mostrado como tal.
enum Agrupamento {
    case hora            // "19"
    case faixaHoraria    // "18–21"
    case diaDaSemana     // "sáb"
    case data            // número do dia (DiaRelatorio.numero)
    case regiao          // geohash de 6 letras

    static func chave(_ data: Date, _ a: Agrupamento, calendario: Calendar = .current) -> String {
        let h = calendario.component(.hour, from: data)
        switch a {
        case .hora:         return String(format: "%02d", h)
        case .faixaHoraria: let i = h / 3 * 3; return String(format: "%02d–%02d", i, i + 3)
        case .diaDaSemana:  return calendario.shortWeekdaySymbols[calendario.component(.weekday, from: data) - 1]
        case .data:         return String(DiaRelatorio.numero(de: data))
        case .regiao:       return ""
        }
    }
}

enum Historico {
    static func turnos(_ turnos: [Turno], em periodo: Periodo, agora: Date = Date()) -> [Turno] {
        let i = periodo.intervalo(agora: agora)
        return turnos.filter { $0.inicio < i.end && ($0.fim ?? agora) > i.start }
    }

    static func ultimos(_ n: Int, de turnos: [Turno]) -> [Turno] {
        Array(turnos.filter { !$0.ativo }.sorted { $0.inicio > $1.inicio }.prefix(n))
    }

    static func agrupar<T>(_ itens: [T], por a: Agrupamento, data: (T) -> Date?, regiao: (T) -> String? = { _ in nil })
        -> [String: [T]] {
        var grupos: [String: [T]] = [:]
        for item in itens {
            let chave: String?
            if a == .regiao { chave = regiao(item) } else { chave = data(item).map { Agrupamento.chave($0, a) } }
            guard let chave else { continue }   // sem dado = fora do grupo (não chutar)
            grupos[chave, default: []].append(item)
        }
        return grupos
    }
}
