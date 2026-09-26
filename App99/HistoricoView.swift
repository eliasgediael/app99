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

// MARK: - Tela

/// Aba Análises: o período em profundidade. Financeiro → tempo → horários → dias → regiões → rotas →
/// o que aconteceu depois → turnos. Cada grupo diz quantos casos tem; nada de "bom" ou "ruim".
struct HistoricoView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nomes = NomesRegioes.shared
    @State private var periodo: Periodo = .ultimos7
    var titulo = "Histórico"

    var body: some View {
        let lista = Historico.turnos(turnos.turnos, em: periodo).sorted { $0.inicio > $1.inicio }
        let a = ResumoAgregado(resumos: lista.map { turnos.resumo($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espaco.s) {
                        ForEach(Periodo.allCases, id: \.self) { p in
                            ChipFiltro(titulo: p.nome, ativo: periodo == p) { periodo = p }
                        }
                    }
                    .padding(.horizontal, Espaco.margem)
                }
                .padding(.horizontal, -Espaco.margem)

                if lista.isEmpty {
                    EstadoVazio(icone: "chart.bar", titulo: "Nenhum turno neste período",
                                texto: "Escolha outro período ou rode um turno: as análises saem só dos seus dados.")
                } else {
                    financeiro(a)
                    tempo(a)
                    horarios(a)
                    if periodo != .hoje && periodo != .ontem { dias(a) }
                    regioes(a)
                    rotas(a)
                    depois(a)
                    turnosLista(lista)
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle(titulo)
    }

    // MARK: Financeiro

    private func financeiro(_ a: ResumoAgregado) -> some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            VStack(alignment: .leading, spacing: Espaco.xs) {
                RotuloSecao("Financeiro")
                Text(Formato.reais(a.confirmado))
                    .font(Tipo.destaque)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Self.subtituloFinanceiro(a))
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
            }
            HStack(alignment: .top, spacing: Espaco.m) {
                MetricaCompacta(a.resultado, rotulo: "após custos") { Formato.reais($0) }
                MetricaCompacta(a.porHora, rotulo: "por hora") { Formato.reais($0) }
                MetricaCompacta(a.porKm, rotulo: "por km") { Formato.reais($0) }
                MetricaCompacta(a.km, rotulo: "rodados") { Formato.km($0) }
            }
            if a.corridasEstimadas > 0 {
                Aviso(.estimativa, Self.tituloEstimadas(a.corridasEstimadas),
                      impacto: "≈ " + Formato.reais(a.estimado) + " fica fora do faturamento confirmado.")
            }
            Text("Ofertas: \(a.ofertasAceitas) aceitas de \(a.ofertas). \"Após custos\" desconta abastecimentos e custos registrados.")
                .font(Tipo.legenda)
                .foregroundStyle(Tema.textoTerciario)
        }
    }

    private static func subtituloFinanceiro(_ a: ResumoAgregado) -> String {
        let turnos = a.turnos == 1 ? "1 turno" : "\(a.turnos) turnos"
        return "faturamento confirmado · " + PainelTurno.corridas(a.corridasConfirmadas) + " · " + turnos
    }

    private static func tituloEstimadas(_ n: Int) -> String {
        n == 1 ? "1 corrida estimada no período" : "\(n) corridas estimadas no período"
    }

    // MARK: Tempo

    private func tempo(_ a: ResumoAgregado) -> some View {
        Bloco("Tempo", subtitulo: "\(Duracao.curta(a.duracao)) de turno") {
            BarraEstados(tempos: a.tempoPorEstado)
            if let p = a.tempoParado {
                LinhaMetrica("Parado (GPS)", Duracao.curta(p))
            }
        }
    }

    // MARK: Horários

    @ViewBuilder
    private func horarios(_ a: ResumoAgregado) -> some View {
        let horas = a.horasDoDia
        if !horas.isEmpty {
            Bloco("Horários", subtitulo: "soma do período por hora do dia · corrida conta na hora em que terminou") {
                GraficoHoras(horas: horas, porHoraDoDia: true)
                VStack(spacing: 0) {
                    ForEach(horas) { h in
                        LinhaHora(h: h)
                        if h.id != horas.last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    // MARK: Dias da semana

    @ViewBuilder
    private func dias(_ a: ResumoAgregado) -> some View {
        let ds = a.diasDaSemana
        if !ds.isEmpty {
            let maior = max(1, ds.map(\.faturamento).max() ?? 1)
            Bloco("Dias da semana", subtitulo: "pelo dia em que o turno começou") {
                VStack(spacing: Espaco.m) {
                    ForEach(ds) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(d.nome.capitalized).font(Tipo.apoio.weight(.semibold)).frame(width: 44, alignment: .leading)
                                Text(Formato.reais(d.faturamento)).font(Tipo.apoio.weight(.semibold)).monospacedDigit()
                                Spacer()
                                Text(Self.textoDia(d)).font(Tipo.legenda).monospacedDigit().foregroundStyle(Tema.textoSecundario)
                            }
                            GeometryReader { g in
                                Capsule().fill(Tema.primaria.opacity(0.7))
                                    .frame(width: max(4, g.size.width * d.faturamento / maior))
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
    }

    private static func textoDia(_ d: ResumoAgregado.DiaSemana) -> String {
        var p = ["\(d.datas.count) dia\(d.datas.count == 1 ? "" : "s")", PainelTurno.corridas(d.corridas)]
        if let ph = d.porHora { p.append(Formato.reais(ph) + "/h") }
        if d.poucosDados { p.append("poucos dados") }
        return p.joined(separator: " · ")
    }

    // MARK: Regiões

    @ViewBuilder
    private func regioes(_ a: ResumoAgregado) -> some View {
        let rs = a.regioes()
        Bloco("Regiões de embarque", subtitulo: "células de ~1 km onde os passageiros embarcaram (GPS)") {
            if rs.isEmpty {
                Text("Sem embarques com GPS neste período.").font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            } else {
                if !nomes.ativo { avisoNomes }
                VStack(spacing: 0) {
                    ForEach(rs.prefix(8)) { g in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nomes.rotulo(g.id)).font(Tipo.apoio.weight(.semibold)).foregroundStyle(Tema.texto)
                                Text(([PainelTurno.corridas(g.corridas),
                                       g.km > 0 ? Formato.km(g.km) : nil,
                                       g.porKm.map { Formato.reais($0) + "/km" },
                                       g.poucosDados ? "poucos dados" : nil] as [String?])
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(Tipo.legenda).monospacedDigit().foregroundStyle(Tema.textoSecundario)
                            }
                            Spacer()
                            Text(Formato.reais(g.faturamento)).font(Tipo.apoio).monospacedDigit().foregroundStyle(Tema.texto)
                        }
                        .padding(.vertical, Espaco.s)
                        if g.id != rs.prefix(8).last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    private var avisoNomes: some View {
        Aviso(.informacao, "Regiões aparecem por código",
              impacto: "Você pode ativar nomes de bairros em Perfil → Privacidade. Para isso, o centro aproximado de cada região é enviado à Apple.",
              acaoTitulo: "Abrir Perfil") { Navegacao.shared.perfilAberto = true }
    }

    // MARK: Rotas

    @ViewBuilder
    private func rotas(_ a: ResumoAgregado) -> some View {
        let rs = a.rotas
        Bloco("Rotas", subtitulo: "região do embarque → região do desembarque") {
            if rs.isEmpty {
                Text("Nenhuma corrida com GPS no embarque e na tela de fim neste período.")
                    .font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            } else {
                VStack(spacing: 0) {
                    ForEach(rs.prefix(8)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(nomes.rotulo(r.origem)) → \(nomes.rotulo(r.destino))")
                                    .font(Tipo.apoio.weight(.semibold)).foregroundStyle(Tema.texto)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(r.corridas)×").font(Tipo.apoio).monospacedDigit().foregroundStyle(Tema.textoSecundario)
                            }
                            Text(Self.textoRota(r)).font(Tipo.legenda).monospacedDigit().foregroundStyle(Tema.textoSecundario)
                        }
                        .padding(.vertical, Espaco.s)
                        if r.id != rs.prefix(8).last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    private static func textoRota(_ r: ResumoAgregado.Rota) -> String {
        var p: [String] = []
        if r.confirmadas > 0 { p.append(Formato.reais(r.faturamento) + " confirmado") }
        if r.km > 0 { p.append(Formato.km(r.km)) }
        if r.comContinuacao > 0 { p.append("\(r.novaEmAte10) de \(r.comContinuacao) com nova corrida em até 10 min") }
        return p.joined(separator: " · ")
    }

    // MARK: O que aconteceu depois

    @ViewBuilder
    private func depois(_ a: ResumoAgregado) -> some View {
        let ds = a.depoisDoDesembarque.filter { $0.casos > 0 }
        Bloco("O que aconteceu depois", subtitulo: "depois de desembarcar em cada região") {
            if ds.isEmpty {
                Text("Precisa de corridas com a tela de fim e o GPS registrados.")
                    .font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            } else {
                VStack(alignment: .leading, spacing: Espaco.m) {
                    ForEach(ds.prefix(6)) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nomes.rotulo(d.regiao)).font(Tipo.apoio.weight(.semibold)).foregroundStyle(Tema.texto)
                            Text(Self.textoDepois(d)).font(Tipo.legenda).foregroundStyle(Tema.textoSecundario)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Só descreve o que aconteceu com você nesses casos. Não é previsão.")
                        .font(Tipo.legenda).foregroundStyle(Tema.textoTerciario)
                }
            }
        }
    }

    private static func textoDepois(_ d: ResumoAgregado.Depois) -> String {
        var t = "Depois de \(d.casos) desembarque\(d.casos == 1 ? "" : "s") aqui: \(d.novaEmAte10) tiveram nova corrida em até 10 min"
            + " e \(d.maisDe10) ficaram mais de 10 min sem corrida."
        if let m = d.mediana { t += " Espera típica: \(Duracao.curta(m))." }
        if d.turnoAcabou > 0 { t += " (\(d.turnoAcabou) no fim do turno, fora da conta.)" }
        if d.poucosDados { t += " Poucos dados." }
        return t
    }

    // MARK: Turnos

    private func turnosLista(_ lista: [Turno]) -> some View {
        Bloco("Turnos") {
            VStack(spacing: 0) {
                ForEach(lista) { t in
                    NavigationLink { ResumoTurnoView(turno: t) } label: {
                        let r = turnos.resumo(t)
                        LinhaNavegacao(ResumoTurnoView.titulo(t), "flag", Formato.reais(r.faturamentoConfirmado.valor ?? 0))
                    }
                    .buttonStyle(.plain)
                    if t.id != lista.last?.id { Divisoria() }
                }
            }
        }
    }
}

extension Periodo {
    var nome: String {
        switch self {
        case .hoje:      return "Hoje"
        case .ontem:     return "Ontem"
        case .ultimos7:  return "7 dias"
        case .ultimos30: return "30 dias"
        case .semana:    return "Esta semana"
        case .mes:       return "Este mês"
        }
    }
}
