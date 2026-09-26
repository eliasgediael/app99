import SwiftUI

// Derivado de ResumoTurno. Nada aqui é guardado.

// MARK: - Por hora

/// Uma hora do relógio. REGRA: a corrida pertence à hora em que terminou (não é dividida).
/// Km e tempo sem corrida são do GPS/estados daquela hora.
struct HoraAtividade: Identifiable {
    let inicio: Date
    var id: Date { inicio }
    var confirmado = 0.0
    var estimado = 0.0
    var corridas = 0            // confirmadas
    var estimadas = 0
    var metros = 0.0
    var semCorrida: TimeInterval = 0
    var tempoTurno: TimeInterval = 0
    var comLeitura: TimeInterval = 0
    var comGPS = false
    var turno: UUID?            // turno que ocupou essa hora (pra abrir o mapa)

    var km: Double { metros / 1000 }
    /// Faturamento ÷ tempo com a leitura ligada nessa hora (pelo menos 15 min; menos que isso distorce).
    var porHora: Double? { comLeitura >= 900 ? confirmado / (comLeitura / 3600) : nil }

    var temDados: Bool { corridas + estimadas > 0 || comLeitura > 0 }

    /// "22:00–23:00"
    var intervaloTexto: String {
        let h = Calendar.current.component(.hour, from: inicio)
        return String(format: "%02d:00–%02d:00", h, (h + 1) % 24)
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
                    if c.confianca == .confirmado {
                        h.corridas += 1
                        h.confirmado += c.valor.valor ?? 0
                    } else {
                        h.estimadas += 1
                        h.estimado += c.valor.valor ?? 0
                    }
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
                        if s.estado != .semLeitura && s.estado != .pausado { h.comLeitura += f.segundos }
                        if h.turno == nil { h.turno = r.turno.id }
                    }
                }
            }
        }
        // Hora sem leitura e sem corrida não tem dado: fica fora (não é R$ 0)
        return g.values.filter { $0.temDados }.sorted { $0.inicio < $1.inicio }
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
            x.comLeitura += h.comLeitura
            x.comGPS = x.comGPS || h.comGPS
            g[k] = x
        }
        return g.values.sorted { $0.inicio < $1.inicio }
    }
}

// MARK: - Linha do tempo

struct ItemAtividade: Identifiable {
    enum Tipo { case turno, corrida, espera, pausa, abastecimento, leitura, oferta }
    let id: String
    let em: Date
    let tipo: Tipo
    let titulo: String
    var detalhe: String?
    var cor: Color
    var corrida: CorridaAnalisada?
    var resumo: ResumoTurno?
}

enum Narrativa {
    static func itens(_ resumos: [ResumoTurno], eventos: [EventoLinha], ofertas: Bool) -> [ItemAtividade] {
        var lista: [ItemAtividade] = []
        for r in resumos {
            let t = r.turno
            let p = t.id.uuidString
            lista.append(ItemAtividade(id: p + "i", em: t.inicio, tipo: .turno, titulo: "Turno iniciado", cor: Tema.primaria))
            if let fim = t.fim {
                lista.append(ItemAtividade(id: p + "f", em: fim, tipo: .turno, titulo: "Turno encerrado",
                                           detalhe: Duracao.curta(r.duracao.valor ?? 0), cor: Tema.primaria))
            }
            for (i, pausa) in t.pausas.enumerated() {
                lista.append(ItemAtividade(id: p + "p\(i)", em: pausa.inicio, tipo: .pausa, titulo: "Pausa",
                                           detalhe: Duracao.curta(pausa.duracao(ate: t.fim ?? Date())), cor: Tema.atencao))
            }
            for c in r.feitas {
                guard let fim = c.terminoVisto else { continue }
                lista.append(ItemAtividade(id: p + "c\(c.id)", em: fim, tipo: .corrida, titulo: c.valorTexto,
                                           detalhe: c.resumoCurto.isEmpty ? nil : c.resumoCurto,
                                           cor: c.estimada ? Tema.atencao : Tema.positivo, corrida: c, resumo: r))
            }
            for (i, s) in r.segmentos.enumerated() where s.estado == .aguardando && s.duracao >= 300 {
                lista.append(ItemAtividade(id: p + "e\(i)", em: s.inicio, tipo: .espera,
                                           titulo: "\(Duracao.curta(s.duracao)) sem corrida", cor: Tema.neutro))
            }
            for c in r.custos {
                lista.append(ItemAtividade(id: c.id.uuidString, em: c.em, tipo: .abastecimento, titulo: c.tipo.nome,
                                           detalhe: Formato.reais(c.valor), cor: Tema.abastecimento))
            }
            // Leitura desligada no meio do turno = período sem registro
            for e in eventos where t.contem(e.data) && e.tipo == .leituraEncerrada {
                guard (t.fim ?? .distantFuture).timeIntervalSince(e.data) > 60 else { continue }
                lista.append(ItemAtividade(id: "l\(e.seq)", em: e.data, tipo: .leitura, titulo: "Leitura desligada",
                                           cor: Tema.textoTerciario))
            }
            if ofertas {
                for o in r.ofertas {
                    lista.append(ItemAtividade(id: p + "o\(o.id)-\(Int(o.em.timeIntervalSince1970))", em: o.em, tipo: .oferta,
                                               titulo: "Oferta " + Formato.reais(Double(o.valorCent) / 100),
                                               detalhe: Formato.km(o.km) + (o.resultado == .aceita ? " · aceita" : ""),
                                               cor: Tema.textoTerciario))
                }
            }
        }
        return lista.sorted { $0.em < $1.em }
    }
}
