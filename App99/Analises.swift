import Foundation

// Análises de vários turnos. Só descrevem o que aconteceu NOS SEUS dados, sempre com a quantidade
// de casos ao lado. Nunca classificam lugar ou horário como "bom" ou "ruim": quem decide é você.

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

    /// Corridas que aconteceram (confirmadas + estimadas), em ordem.
    static func feitas(_ r: ResumoTurno) -> [CorridaAnalisada] {
        r.corridas.filter { $0.confianca == .confirmado || $0.confianca == .estimado }
            .sorted { ($0.inicioVisto ?? .distantPast) < ($1.inicioVisto ?? .distantPast) }
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
