import SwiftUI

// MARK: - Soma de vários turnos

/// Totais de um conjunto de turnos. Só descreve o que aconteceu nos seus dados;
/// cada grupo mostra quantos dados tem, pra ninguém tirar conclusão de 1 corrida.
struct ResumoAgregado {
    let resumos: [ResumoTurno]

    var turnos: Int { resumos.count }
    var duracao: TimeInterval { resumos.reduce(0) { $0 + ($1.duracao.valor ?? 0) } }
    var confirmado: Double { resumos.reduce(0) { $0 + ($1.faturamentoConfirmado.valor ?? 0) } }
    var estimado: Double { resumos.reduce(0) { $0 + ($1.faturamentoEstimado.valor ?? 0) } }
    var custosRegistrados: Double { resumos.reduce(0) { $0 + ($1.combustivel.valor ?? 0) + ($1.outrosCustos.valor ?? 0) } }
    var corridasConfirmadas: Int { resumos.reduce(0) { $0 + $1.corridasConfirmadas } }
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

// MARK: - Tela

struct HistoricoView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @State private var periodo: Periodo = .ultimos7

    var body: some View {
        let lista = Historico.turnos(turnos.turnos, em: periodo).sorted { $0.inicio > $1.inicio }
        let a = ResumoAgregado(resumos: lista.map { turnos.resumo($0) })
        List {
            Section {
                Picker("Período", selection: $periodo) {
                    ForEach(Periodo.allCases, id: \.self) { Text($0.nome).tag($0) }
                }
            }
            if lista.isEmpty {
                Text("Nenhum turno neste período.").foregroundStyle(.secondary)
            } else {
                principais(a)
                tempo(a)
                faixas(a)
                if periodo != .hoje && periodo != .ontem { diasDaSemana(a) }
                regioes(a)
                turnosLista(lista)
            }
        }
        .navigationTitle("Histórico")
    }

    private func principais(_ a: ResumoAgregado) -> some View {
        Section {
            NumeroDestaque(valor: Formato.reais(a.confirmado), rotulo: "faturamento confirmado", grande: true)
            if a.corridasEstimadas > 0 {
                Text("+ ≈ \(Formato.reais(a.estimado)) estimado (\(a.corridasEstimadas) corridas, fora do total)")
                    .font(.caption).foregroundStyle(.orange)
            }
            Campo("Resultado após custos", a.resultado) { Formato.reais($0) }
            Campo("R$/hora", a.porHora) { Formato.reais($0) }
            Campo("R$/km", a.porKm) { Formato.reais($0) }
            Campo("Distância", a.km) { Formato.km($0) }
            LabeledContent("Tempo de turno", value: Duracao.curta(a.duracao))
            LabeledContent("Corridas confirmadas", value: "\(a.corridasConfirmadas)")
            LabeledContent("Ofertas aceitas", value: "\(a.ofertasAceitas) de \(a.ofertas)")
            LabeledContent("Turnos", value: "\(a.turnos)")
        }
    }

    private func tempo(_ a: ResumoAgregado) -> some View {
        Section("Onde foi o tempo") {
            ForEach(EstadoMotorista.allCases, id: \.self) { e in
                if let s = a.tempoPorEstado[e], s >= 60 {
                    LabeledContent(e.nome) {
                        Text(Duracao.curta(s) + (a.duracao > 0 ? String(format: "  %.0f%%", s / a.duracao * 100) : ""))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func faixas(_ a: ResumoAgregado) -> some View {
        Section {
            ForEach(a.grupos(.faixaHoraria)) { g in grupo(g.id + "h", g) }
        } header: {
            Text("Por horário")
        } footer: {
            Text("R$/h = faturamento confirmado das corridas que terminaram na faixa ÷ horas de turno nela. \"poucos dados\" = menos de 3 corridas.")
        }
    }

    private func diasDaSemana(_ a: ResumoAgregado) -> some View {
        Section("Por dia da semana") {
            ForEach(a.grupos(.diaDaSemana)) { g in grupo(g.id, g) }
        }
    }

    @ViewBuilder
    private func regioes(_ a: ResumoAgregado) -> some View {
        let rs = a.regioes()
        if !rs.isEmpty {
            Section {
                ForEach(rs.prefix(8)) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Região \(g.id)").font(.subheadline.bold())
                            Spacer()
                            Text(Formato.reais(g.faturamento)).monospacedDigit()
                        }
                        Text("\(g.corridas) corrida\(g.corridas == 1 ? "" : "s")"
                             + (g.porKm.map { " · " + Formato.reais($0) + "/km" } ?? "")
                             + (g.poucosDados ? " · poucos dados" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Regiões de embarque")
            } footer: {
                Text("Células de ~1 km onde os passageiros embarcaram, pelo seu GPS. Só corridas confirmadas.")
            }
        }
    }

    private func turnosLista(_ lista: [Turno]) -> some View {
        Section("Turnos") {
            ForEach(lista) { t in
                NavigationLink {
                    ResumoTurnoView(turno: t)
                } label: {
                    let r = turnos.resumo(t)
                    LabeledContent(ResumoTurnoView.titulo(t)) {
                        Text(Formato.reais(r.faturamentoConfirmado.valor ?? 0)).monospacedDigit()
                    }
                }
            }
        }
    }

    private func grupo(_ nome: String, _ g: ResumoAgregado.Grupo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(nome).font(.subheadline.bold())
                Spacer()
                Text(Formato.reais(g.faturamento)).monospacedDigit()
            }
            Text((["\(g.corridas) corridas", "\(g.ofertas) ofertas",
                  g.porHora.map { Formato.reais($0) + "/h" }, g.poucosDados ? "poucos dados" : nil] as [String?])
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Periodo {
    var nome: String {
        switch self {
        case .hoje:      return "Hoje"
        case .ontem:     return "Ontem"
        case .ultimos7:  return "Últimos 7 dias"
        case .ultimos30: return "Últimos 30 dias"
        case .semana:    return "Esta semana"
        case .mes:       return "Este mês"
        }
    }
}

/// Bloco curto do histórico pra tela inicial: hoje e 7 dias, e um link pro resto.
struct HistoricoCurto: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared

    var body: some View {
        if !turnos.turnos.isEmpty {
            Section {
                linhaPeriodo(.hoje)
                linhaPeriodo(.ultimos7)
                NavigationLink("Ver histórico") { HistoricoView() }
            } header: {
                Text("Histórico")
            }
        }
    }

    private func linhaPeriodo(_ p: Periodo) -> some View {
        let a = ResumoAgregado(resumos: Historico.turnos(turnos.turnos, em: p).map { turnos.resumo($0) })
        return LabeledContent(p.nome) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Formato.reais(a.confirmado)).monospacedDigit().bold()
                Text("\(a.corridasConfirmadas) corridas" + (a.porHora.valor.map { " · " + Formato.reais($0) + "/h" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
