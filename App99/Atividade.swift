import SwiftUI

// Leituras derivadas pra Atividade e Análises. Tudo sai de ResumoTurno (que sai da linha do tempo,
// do GPS e dos custos). Nada aqui é guardado: é só outra forma de olhar os mesmos dados.

// MARK: - Por hora

/// Uma hora do relógio. REGRA: a corrida pertence à hora em que terminou (não é dividida).
/// Km e tempo sem corrida são do GPS/estados daquela hora.
struct HoraAtividade: Identifiable {
    let inicio: Date
    var id: Date { inicio }
    var confirmado = 0.0
    var estimado = 0.0
    var corridas = 0            // confirmadas + estimadas
    var estimadas = 0
    var metros = 0.0
    var semCorrida: TimeInterval = 0
    var tempoTurno: TimeInterval = 0
    var comGPS = false
    var turno: UUID?            // turno que ocupou essa hora (pra abrir o mapa)

    var km: Double { metros / 1000 }
    /// R$/h só com pelo menos 15 min de turno na hora (menos que isso distorce).
    var porHora: Double? { tempoTurno >= 900 ? confirmado / (tempoTurno / 3600) : nil }

    /// "21–22"
    var rotulo: String {
        let h = Calendar.current.component(.hour, from: inicio)
        return String(format: "%02d–%02d", h, (h + 1) % 24)
    }
}

enum Horas {
    static func inicioDaHora(_ d: Date, _ cal: Calendar = .current) -> Date {
        cal.dateInterval(of: .hour, for: d)?.start ?? d
    }

    /// Pedaços de um intervalo por hora do relógio.
    static func fatias(de inicio: Date, ate fim: Date, _ cal: Calendar = .current) -> [(hora: Date, segundos: TimeInterval)] {
        var r: [(Date, TimeInterval)] = []
        var t = inicio
        while t < fim {
            let h = inicioDaHora(t, cal)
            let proxima = cal.date(byAdding: .hour, value: 1, to: h) ?? fim
            let ate = min(proxima, fim)
            r.append((h, ate.timeIntervalSince(t)))
            t = ate
        }
        return r
    }

    /// Horas (do relógio, em ordem) com algo acontecendo nos turnos dados.
    static func porHora(_ resumos: [ResumoTurno]) -> [HoraAtividade] {
        var g: [Date: HoraAtividade] = [:]
        func mexer(_ h: Date, _ f: (inout HoraAtividade) -> Void) {
            var x = g[h] ?? HoraAtividade(inicio: h)
            f(&x)
            g[h] = x
        }
        for r in resumos {
            for c in r.corridas where c.confianca == .confirmado || c.confianca == .estimado {
                guard let fim = c.terminoVisto else { continue }
                mexer(inicioDaHora(fim)) { h in
                    h.corridas += 1
                    if c.confianca == .confirmado { h.confirmado += c.valor.valor ?? 0 }
                    else { h.estimado += c.valor.valor ?? 0; h.estimadas += 1 }
                }
            }
            for t in r.trajeto.trechos {
                mexer(inicioDaHora(t.meio)) { $0.metros += t.metros; $0.comGPS = true }
            }
            for s in r.segmentos {
                for f in fatias(de: s.inicio, ate: s.fim) {
                    mexer(f.hora) { h in
                        h.tempoTurno += f.segundos
                        if s.estado == .aguardando { h.semCorrida += f.segundos }
                        if h.turno == nil { h.turno = r.turno.id }
                    }
                }
            }
        }
        return g.values.filter { $0.tempoTurno > 0 || $0.corridas > 0 }.sorted { $0.inicio < $1.inicio }
    }

    /// Soma por hora do dia (0–23) pra comparar vários dias. `inicio` vira uma data de referência.
    static func porHoraDoDia(_ horas: [HoraAtividade], _ cal: Calendar = .current) -> [HoraAtividade] {
        var g: [Int: HoraAtividade] = [:]
        let base = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        for h in horas {
            let k = cal.component(.hour, from: h.inicio)
            var x = g[k] ?? HoraAtividade(inicio: cal.date(byAdding: .hour, value: k, to: base) ?? base)
            x.confirmado += h.confirmado
            x.estimado += h.estimado
            x.corridas += h.corridas
            x.estimadas += h.estimadas
            x.metros += h.metros
            x.semCorrida += h.semCorrida
            x.tempoTurno += h.tempoTurno
            x.comGPS = x.comGPS || h.comGPS
            g[k] = x
        }
        return g.values.sorted { $0.inicio < $1.inicio }
    }
}

// MARK: - Narrativa

enum FiltroAtividade: String, CaseIterable, Identifiable {
    case tudo, corridas, ofertas, turno
    var id: Self { self }
    var nome: String {
        switch self {
        case .tudo:     return "Tudo"
        case .corridas: return "Corridas"
        case .ofertas:  return "Ofertas"
        case .turno:    return "Turno"
        }
    }
}

/// Um acontecimento contado em linguagem de motorista.
struct ItemAtividade: Identifiable {
    let id: String
    let em: Date
    let categoria: FiltroAtividade
    let titulo: String
    var detalhe: String?
    let icone: String
    let cor: Color
    var corrida: CorridaAnalisada?
    var resumo: ResumoTurno?
    /// Oferta, espera etc. aparecem mais discretos que a corrida.
    var discreto = false
}

enum Narrativa {
    /// Turnos do dia → história em ordem. `eventos`: linha do tempo (pra GPS e leitura liga/desliga).
    static func itens(_ resumos: [ResumoTurno], eventos: [EventoLinha]) -> [ItemAtividade] {
        var lista: [ItemAtividade] = []
        for r in resumos {
            let t = r.turno
            let pref = t.id.uuidString
            lista.append(ItemAtividade(id: pref + "-ini", em: t.inicio, categoria: .turno, titulo: "Turno iniciado",
                                       icone: "flag", cor: Tema.primaria))
            for (i, p) in t.pausas.enumerated() {
                lista.append(ItemAtividade(id: pref + "-p\(i)", em: p.inicio, categoria: .turno, titulo: "Pausa",
                                           detalhe: Duracao.curta(p.duracao(ate: t.fim ?? Date())),
                                           icone: "pause.circle", cor: Tema.atencao))
                if let f = p.fim {
                    lista.append(ItemAtividade(id: pref + "-pf\(i)", em: f, categoria: .turno, titulo: "Fim da pausa",
                                               icone: "play.circle", cor: Tema.atencao, discreto: true))
                }
            }
            if let fim = t.fim {
                lista.append(ItemAtividade(id: pref + "-fim", em: fim, categoria: .turno, titulo: "Turno encerrado",
                                           detalhe: "\(Duracao.curta(r.duracao.valor ?? 0)) · \(Formato.reais(r.faturamentoConfirmado.valor ?? 0)) confirmado",
                                           icone: "flag.checkered", cor: Tema.primaria))
            }

            for c in r.corridas {
                let cid = pref + "-c\(c.id)"
                if let a = c.aceiteEm {
                    let oferta = c.valorOfertaCent.map { "oferta de " + Formato.reais(Double($0) / 100) }
                    let busca = c.buscaM.map { "busca " + Formato.km(Double($0) / 1000) }
                    lista.append(ItemAtividade(id: cid + "-a", em: a, categoria: .corridas,
                                               titulo: c.cancelada ? "Corrida aceita" : "Corrida aceita · indo buscar",
                                               detalhe: [oferta, busca].compactMap { $0 }.joined(separator: " · "),
                                               icone: "car", cor: Tema.mapaIndoBuscar, corrida: c, resumo: r))
                }
                if let b = c.aBordoEm {
                    lista.append(ItemAtividade(id: cid + "-b", em: b, categoria: .corridas, titulo: "Passageiro a bordo",
                                               icone: "person.fill", cor: Tema.mapaEmCorrida, corrida: c, resumo: r))
                }
                if let f = c.terminoVisto, c.confianca != nil || c.cancelada {
                    lista.append(fim(c, em: f, id: cid + "-f", r: r))
                }
            }

            for o in r.ofertas {
                let resultado: String
                switch o.resultado {
                case .aceita:    resultado = "aceita"
                case .naoAceita: resultado = "não aceita"
                case .emAberto:  resultado = "na tela"
                }
                lista.append(ItemAtividade(id: pref + "-o\(o.id)-\(Int(o.em.timeIntervalSince1970))", em: o.em, categoria: .ofertas,
                                           titulo: "Oferta recebida",
                                           detalhe: ([Formato.reais(Double(o.valorCent) / 100), Formato.km(o.km),
                                                      o.porKm.map { Formato.reais($0) + "/km" }, resultado] as [String?])
                                               .compactMap { $0 }.joined(separator: " · "),
                                           icone: "tag", cor: Tema.neutro, discreto: true))
            }

            for (i, s) in r.segmentos.enumerated() where s.estado == .aguardando && s.duracao >= 180 {
                lista.append(ItemAtividade(id: pref + "-e\(i)", em: s.inicio, categoria: .turno,
                                           titulo: "Sem corrida · \(Duracao.curta(s.duracao))",
                                           icone: "hourglass", cor: Tema.neutro, discreto: true))
            }

            for c in r.custos {
                lista.append(ItemAtividade(id: c.id.uuidString, em: c.em, categoria: .turno, titulo: c.tipo.nome,
                                           detalhe: [Formato.reais(c.valor), c.litros.map { String(format: "%.2f L", $0).replacingOccurrences(of: ".", with: ",") }]
                                               .compactMap { $0 }.joined(separator: " · "),
                                           icone: c.tipo == .combustivel ? "fuelpump" : "creditcard", cor: .purple))
            }

            for e in eventos where t.contem(e.data) {
                switch e.tipo {
                case .gpsSemSinal:
                    lista.append(ItemAtividade(id: "g\(e.seq)", em: e.data, categoria: .turno, titulo: "GPS sem sinal",
                                               detalhe: "os km desse trecho não entram na conta",
                                               icone: "location.slash", cor: Tema.atencao, discreto: true))
                case .gpsRetomado:
                    lista.append(ItemAtividade(id: "g\(e.seq)", em: e.data, categoria: .turno, titulo: "GPS voltou",
                                               icone: "location", cor: Tema.neutro, discreto: true))
                case .leituraIniciada:
                    lista.append(ItemAtividade(id: "l\(e.seq)", em: e.data, categoria: .turno, titulo: "Leitura da tela ligada",
                                               icone: "record.circle", cor: Tema.neutro, discreto: true))
                case .leituraEncerrada:
                    lista.append(ItemAtividade(id: "l\(e.seq)", em: e.data, categoria: .turno, titulo: "Leitura da tela desligada",
                                               detalhe: "o que aconteceu depois disso não foi registrado",
                                               icone: "stop.circle", cor: Tema.atencao, discreto: true))
                default: break
                }
            }
        }
        return lista.sorted { $0.em < $1.em }
    }

    private static func fim(_ c: CorridaAnalisada, em: Date, id: String, r: ResumoTurno) -> ItemAtividade {
        let km = c.kmGPS.valor.map(Formato.km)
        let dur = c.duracao.valor.map(Duracao.curta)
        if c.cancelada {
            return ItemAtividade(id: id, em: em, categoria: .corridas, titulo: "Corrida cancelada",
                                 detalhe: "não entra em nenhum total", icone: "xmark.circle",
                                 cor: Tema.textoTerciario, corrida: c, resumo: r)
        }
        switch c.confianca {
        case .confirmado?:
            return ItemAtividade(id: id, em: em, categoria: .corridas, titulo: "Corrida finalizada",
                                 detalhe: [c.valorTexto, km, dur].compactMap { $0 }.joined(separator: " · "),
                                 icone: "checkmark.circle.fill", cor: Tema.positivo, corrida: c, resumo: r)
        case .estimado?:
            return ItemAtividade(id: id, em: em, categoria: .corridas, titulo: "Corrida finalizada · estimada",
                                 detalhe: [c.valorTexto, "fora do total", km].compactMap { $0 }.joined(separator: " · "),
                                 icone: "questionmark.circle.fill", cor: Tema.atencao, corrida: c, resumo: r)
        default:
            return ItemAtividade(id: id, em: em, categoria: .corridas, titulo: "Corrida sem confirmação",
                                 detalhe: "sem valor identificado · toque pra ver o motivo",
                                 icone: "circle.dashed", cor: Tema.neutro, corrida: c, resumo: r)
        }
    }
}
