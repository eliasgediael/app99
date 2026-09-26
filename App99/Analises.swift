import Foundation

// Análises descrevem o que aconteceu nos dados do usuário, sem classificar lugar ou horário.

// MARK: - Soma de vários turnos

/// Totais de um conjunto de turnos.
struct ResumoAgregado {
    let resumos: [ResumoTurno]

    var turnos: Int { resumos.count }
    var duracao: TimeInterval { resumos.reduce(0) { $0 + ($1.duracao.valor ?? 0) } }
    var confirmado: Double { resumos.reduce(0) { $0 + ($1.faturamentoConfirmado.valor ?? 0) } }
    var estimado: Double { resumos.reduce(0) { $0 + ($1.faturamentoEstimado.valor ?? 0) } }
    var combustivel: Double { resumos.reduce(0) { $0 + ($1.combustivel.valor ?? 0) } }
    var custosRegistrados: Double { resumos.reduce(0) { $0 + ($1.combustivel.valor ?? 0) + ($1.outrosCustos.valor ?? 0) } }
    var corridasConfirmadas: Int { resumos.reduce(0) { $0 + $1.corridasConfirmadas } }
    var corridasFeitas: Int { resumos.reduce(0) { $0 + $1.corridasFeitas } }
    var corridasEstimadas: Int { resumos.reduce(0) { $0 + $1.corridasEstimadas } }
    var ofertas: Int { resumos.reduce(0) { $0 + $1.ofertas.count } }
    var ofertasAceitas: Int { resumos.reduce(0) { $0 + $1.ofertas.filter { $0.resultado == .aceita }.count } }

    var tempoPorEstado: [EstadoMotorista: TimeInterval] {
        resumos.reduce(into: [:]) { t, r in for (e, s) in r.tempoPorEstado { t[e, default: 0] += s } }
    }

    // Distância: só dos turnos com GPS (e R$/km só com o faturamento desses mesmos turnos)
    private var comGPS: [ResumoTurno] { resumos.filter { $0.temGPS } }

    var km: Medida {
        guard !comGPS.isEmpty else { return .indeterminada(.gps, "nenhum turno com GPS") }
        let total = comGPS.reduce(0) { $0 + ($1.km.valor ?? 0) }
        let parcial = comGPS.count < resumos.count
        return Medida(valor: total, confianca: parcial ? .estimado : .confirmado, fonte: .gps,
                      nota: parcial ? "só \(comGPS.count) de \(resumos.count) turnos tinham GPS" : nil)
    }
    var porKm: Medida {
        let km = comGPS.reduce(0) { $0 + ($1.km.valor ?? 0) }
        guard km > 0 else { return .indeterminada(.calculo, "sem km de GPS") }
        let fat = comGPS.reduce(0) { $0 + ($1.faturamentoConfirmado.valor ?? 0) }
        return Medida(valor: fat / km, confianca: comGPS.count < resumos.count ? .estimado : .confirmado,
                      fonte: .calculo, nota: "confirmado ÷ km, só turnos com GPS")
    }
    var porHora: Medida {
        guard duracao > 0 else { return .indeterminada(.calculo, "sem turnos") }
        return Medida(valor: confirmado / (duracao / 3600), confianca: .confirmado, fonte: .calculo, nota: "confirmado ÷ horas de turno")
    }
    var resultado: Medida {
        Medida(valor: confirmado - custosRegistrados, confianca: .estimado, fonte: .calculo,
               nota: "confirmado − abastecimentos e custos registrados")
    }

    // MARK: Grupos

    struct Grupo: Identifiable {
        let id: String
        var faturamento = 0.0
        var corridas = 0
        var ofertas = 0
        var horas = 0.0
        var km = 0.0
        var porHora: Double? { horas >= 0.25 ? faturamento / horas : nil }
        var porKm: Double? { km > 0 ? faturamento / km : nil }
        var poucosDados: Bool { corridas < 3 }
    }

    /// Por faixa horária ou dia da semana: faturamento das corridas confirmadas (pela hora do fim),
    /// ofertas recebidas e horas de turno naquele grupo (pra dar R$/h).
    func grupos(_ a: Agrupamento) -> [Grupo] {
        var g: [String: Grupo] = [:]
        for r in resumos {
            for c in r.corridas where c.confianca == .confirmado {
                guard let quando = c.fimEm ?? c.encerradaEm ?? c.aceiteEm else { continue }
                let k = Agrupamento.chave(quando, a)
                g[k, default: Grupo(id: k)].faturamento += c.valor.valor ?? 0
                g[k, default: Grupo(id: k)].corridas += 1
            }
            for o in r.ofertas {
                let k = Agrupamento.chave(o.em, a)
                g[k, default: Grupo(id: k)].ofertas += 1
            }
            for (k, s) in Self.horasPor(a, de: r.turno.inicio, ate: r.turno.fim ?? Date()) {
                g[k, default: Grupo(id: k)].horas += s / 3600
            }
        }
        return g.values.sorted { $0.id < $1.id }
    }

    /// Por região de embarque (só corridas confirmadas com GPS no embarque).
    func regioes() -> [Grupo] {
        var g: [String: Grupo] = [:]
        for r in resumos {
            for c in r.corridas where c.confianca == .confirmado {
                guard let k = c.regiaoOrigem else { continue }
                g[k, default: Grupo(id: k)].faturamento += c.valor.valor ?? 0
                g[k, default: Grupo(id: k)].corridas += 1
                g[k, default: Grupo(id: k)].km += c.kmGPS.valor ?? 0
            }
        }
        return g.values.sorted { $0.faturamento > $1.faturamento }
    }

    /// Divide um intervalo em pedaços por hora e soma os segundos em cada grupo.
    static func horasPor(_ a: Agrupamento, de inicio: Date, ate fim: Date, calendario: Calendar = .current) -> [String: TimeInterval] {
        var r: [String: TimeInterval] = [:]
        var t = inicio
        while t < fim {
            let proxima = calendario.nextDate(after: t, matching: DateComponents(minute: 0, second: 0),
                                              matchingPolicy: .nextTime) ?? fim
            let ate = min(proxima, fim)
            r[Agrupamento.chave(t, a), default: 0] += ate.timeIntervalSince(t)
            t = ate
        }
        return r
    }
}

extension Periodo {
    var nome: String {
        switch self {
        case .hoje:      return "Hoje"
        case .ontem:     return "Ontem"
        case .ultimos7:  return "7 dias"
        case .ultimos30: return "30 dias"
        case .semana:    return "Semana"
        case .mes:       return "Mês"
        }
    }

    /// Mesmo tamanho, logo antes (pra comparar).
    func anterior(agora: Date = Date()) -> DateInterval {
        let i = intervalo(agora: agora)
        return DateInterval(start: i.start.addingTimeInterval(-i.duration), end: i.start)
    }
}

extension Historico {
    static func turnos(_ turnos: [Turno], entre i: DateInterval) -> [Turno] {
        turnos.filter { $0.inicio >= i.start && $0.inicio < i.end }
    }
}

extension ResumoAgregado {

    /// Hora do dia (0–23) somando todos os dias do período.
    var horasDoDia: [HoraAtividade] { Horas.porHoraDoDia(Horas.porHora(resumos)) }

    /// Tempo parado segundo o GPS (só turnos com GPS).
    var tempoParado: TimeInterval? {
        let com = resumos.compactMap { $0.tempoParado.valor }
        return com.isEmpty ? nil : com.reduce(0, +)
    }

    // MARK: Dias da semana

    struct DiaSemana: Identifiable {
        let dia: Int                 // 1 = domingo (Calendar)
        var id: Int { dia }
        var nome: String { Calendar.current.shortWeekdaySymbols[dia - 1].replacingOccurrences(of: ".", with: "") }
        var faturamento = 0.0
        var corridas = 0
        var horas = 0.0
        var datas: Set<Date> = []
        var porHora: Double? { horas >= 0.25 ? faturamento / horas : nil }
        var poucosDados: Bool { corridas < 3 }
    }

    /// Pelo dia em que cada turno começou (igual ao resto do app).
    var diasDaSemana: [DiaSemana] {
        var g: [Int: DiaSemana] = [:]
        let cal = Calendar.current
        for r in resumos {
            let d = cal.component(.weekday, from: r.turno.inicio)
            var x = g[d] ?? DiaSemana(dia: d)
            x.faturamento += r.faturamentoConfirmado.valor ?? 0
            x.corridas += r.corridasConfirmadas
            x.horas += (r.duracao.valor ?? 0) / 3600
            x.datas.insert(cal.startOfDay(for: r.turno.inicio))
            g[d] = x
        }
        // Semana começando na segunda
        return g.values.sorted { ($0.dia + 5) % 7 < ($1.dia + 5) % 7 }
    }

    // MARK: Rotas

    struct Rota: Identifiable {
        let origem: String
        let destino: String
        var id: String { origem + ">" + destino }
        var corridas = 0
        var confirmadas = 0
        var faturamento = 0.0
        var km = 0.0
        var novaEmAte10 = 0
        var comContinuacao = 0       // casos em que dava pra saber o que veio depois
    }

    /// Região do embarque → região do desembarque (só corridas com GPS nas duas pontas).
    var rotas: [Rota] {
        var g: [String: Rota] = [:]
        for r in resumos {
            let feitas = Self.feitas(r)
            for (i, c) in feitas.enumerated() {
                guard let o = c.regiaoOrigem, let d = c.regiaoDestino else { continue }
                var x = g[o + ">" + d] ?? Rota(origem: o, destino: d)
                x.corridas += 1
                if c.confianca == .confirmado {
                    x.confirmadas += 1
                    x.faturamento += c.valor.valor ?? 0
                }
                x.km += c.kmGPS.valor ?? 0
                switch Self.depois(c, seguinte: i + 1 < feitas.count ? feitas[i + 1] : nil, turno: r.turno) {
                case .nova(let s)?: x.comContinuacao += 1; if s <= 600 { x.novaEmAte10 += 1 }
                case .semCorrida?:  x.comContinuacao += 1
                default: break
                }
                g[x.id] = x
            }
        }
        return g.values.sorted { $0.corridas > $1.corridas }
    }

    // MARK: O que aconteceu depois

    struct Depois: Identifiable {
        let regiao: String
        var id: String { regiao }
        var desembarques = 0
        var novaEmAte10 = 0
        var maisDe10 = 0
        var turnoAcabou = 0
        var esperas: [TimeInterval] = []   // até a próxima corrida (quando houve)

        var casos: Int { novaEmAte10 + maisDe10 }
        var poucosDados: Bool { casos < 3 }
        var mediana: TimeInterval? {
            guard !esperas.isEmpty else { return nil }
            let s = esperas.sorted()
            return s[s.count / 2]
        }
    }

    enum Seguinte {
        case nova(TimeInterval)     // próxima corrida começou X s depois do desembarque
        case semCorrida             // turno seguiu mais de 10 min sem corrida
        case turnoAcabou            // turno terminou antes de 10 min: não dá pra dizer
    }

    /// Depois do desembarque em cada região: nova corrida em até 10 min, ou mais de 10 min sem corrida.
    var depoisDoDesembarque: [Depois] {
        var g: [String: Depois] = [:]
        for r in resumos {
            let feitas = Self.feitas(r)
            for (i, c) in feitas.enumerated() {
                guard let reg = c.regiaoDestino else { continue }
                var x = g[reg] ?? Depois(regiao: reg)
                x.desembarques += 1
                switch Self.depois(c, seguinte: i + 1 < feitas.count ? feitas[i + 1] : nil, turno: r.turno) {
                case .nova(let s)?:
                    if s <= 600 { x.novaEmAte10 += 1 } else { x.maisDe10 += 1 }
                    x.esperas.append(s)
                case .semCorrida?: x.maisDe10 += 1
                case .turnoAcabou?: x.turnoAcabou += 1
                case nil: break
                }
                g[reg] = x
            }
        }
        return g.values.sorted { $0.desembarques > $1.desembarques }
    }

    static func feitas(_ r: ResumoTurno) -> [CorridaAnalisada] {
        r.feitas.sorted { ($0.inicioVisto ?? .distantPast) < ($1.inicioVisto ?? .distantPast) }
    }

    static func depois(_ c: CorridaAnalisada, seguinte: CorridaAnalisada?, turno: Turno) -> Seguinte? {
        guard let fim = c.fimEm else { return nil }   // sem tela de fim não se sabe quando desembarcou
        if let s = seguinte, let ini = s.aceiteEm ?? s.aBordoEm {
            return .nova(max(0, ini.timeIntervalSince(fim)))
        }
        let ate = turno.fim ?? Date()
        return ate.timeIntervalSince(fim) > 600 ? .semCorrida : .turnoAcabou
    }
}
