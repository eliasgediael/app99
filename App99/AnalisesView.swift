import SwiftUI
import Charts

struct AnalisesView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nomes = NomesRegioes.shared
    @State private var periodo: Periodo = .ultimos7

    var body: some View {
        let registrados = turnos.turnosComRegistro
        let lista = Historico.turnos(registrados, em: periodo).sorted { $0.inicio > $1.inicio }
        let a = ResumoAgregado(resumos: lista.map { turnos.resumo($0) })
        let antes = ResumoAgregado(resumos: Historico.turnos(registrados, entre: periodo.anterior()).map { turnos.resumo($0) })

        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                FiltrosChips(opcoes: Periodo.allCases, nome: { $0.nome }, selecao: $periodo)
                    .padding(.horizontal, -Espaco.margem)

                if lista.isEmpty {
                    EstadoVazio(icone: "chart.bar", titulo: "Sem dados neste período")
                } else {
                    topo(a, antes: antes)
                    if !a.tempoPorEstado.isEmpty {
                        Secao("Tempo") { BarraEstados(tempos: a.tempoPorEstado) }
                    }
                    let horas = a.horasDoDia
                    if !horas.isEmpty {
                        Secao("Faturamento por hora") { GraficoHoras(horas: horas) }
                    }
                    indicadores(a)
                    porDia(a)
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
        .navigationTitle("Análises")
    }

    // MARK: Topo

    private func topo(_ a: ResumoAgregado, antes: ResumoAgregado) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Formato.reais(a.confirmado))
                .font(Tipo.heroi)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Faturamento total (\(periodo.nome.lowercased()))")
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
            // Só compara quando o período anterior tem turnos e faturamento
            if antes.turnos > 0, antes.confirmado > 0 {
                let d = (a.confirmado - antes.confirmado) / antes.confirmado
                HStack(spacing: 4) {
                    Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.0f%% vs período anterior", d * 100).replacingOccurrences(of: ".", with: ","))
                }
                .font(Tipo.legenda.weight(.semibold))
                .foregroundStyle(Tema.textoSecundario)
            }
        }
    }

    private func indicadores(_ a: ResumoAgregado) -> some View {
        GradeMetricas {
            Metrica(a.porHora, "por hora") { Formato.reais($0) }
            Metrica(a.porKm, "por km") { Formato.reais($0) }
            Metrica(a.km, "km") { Formato.km($0) }
            Metrica(Duracao.curta(a.duracao), "de turno")
            Metrica("\(a.corridasConfirmadas)", a.corridasEstimadas > 0 ? "corridas · \(a.corridasEstimadas) ≈" : "corridas")
            Metrica(a.ofertas > 0 ? "\(a.ofertasAceitas)/\(a.ofertas)" : "—", "ofertas aceitas")
            Metrica(a.combustivel > 0 ? Formato.reais(a.combustivel) : "—", "combustível")
            Metrica(a.resultado, "resultado") { Formato.reais($0) }
            Metrica("\(a.turnos)", a.turnos == 1 ? "turno" : "turnos")
        }
    }

    // MARK: Por dia

    @ViewBuilder
    private func porDia(_ a: ResumoAgregado) -> some View {
        let dias = Dictionary(grouping: a.resumos) { Calendar.current.startOfDay(for: $0.turno.inicio) }
            .map { ResumoDia(dia: $0.key, resumos: $0.value) }
            .sorted { $0.dia < $1.dia }
        let longo = periodo != .hoje && periodo != .ontem
        if longo && !dias.isEmpty {
            Secao("Por dia") {
                if dias.count > 1 { GraficoDias(dias: dias) }
                SemanaLista(semana: a.diasDaSemana)
            }
        }
    }

    // MARK: Regiões, rotas, depois

    @ViewBuilder
    private func regioes(_ a: ResumoAgregado) -> some View {
        let rs = Array(a.regioes().prefix(8))
        if !rs.isEmpty {
            Secao("Regiões de embarque") {
                VStack(spacing: 0) {
                    ForEach(rs) { g in
                        linhaDado(nomes.rotulo(g.id),
                                  [Datas.corridas(g.corridas), g.porKm.map { Formato.reais($0) + "/km" }].compactMap { $0 }.joined(separator: " · "),
                                  Formato.reais(g.faturamento))
                        if g.id != rs.last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rotas(_ a: ResumoAgregado) -> some View {
        let rs = Array(a.rotas.prefix(8))
        if !rs.isEmpty {
            Secao("Rotas") {
                VStack(spacing: 0) {
                    ForEach(rs) { r in
                        linhaDado("\(nomes.rotulo(r.origem)) → \(nomes.rotulo(r.destino))",
                                  Self.detalheRota(r),
                                  r.confirmadas > 0 ? Formato.reais(r.faturamento) : "—")
                        if r.id != rs.last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    private static func detalheRota(_ r: ResumoAgregado.Rota) -> String {
        var p = ["\(r.corridas)×"]
        if r.km > 0 { p.append(Formato.km(r.km)) }
        if r.comContinuacao > 0 { p.append("\(r.novaEmAte10)/\(r.comContinuacao) nova em 10 min") }
        return p.joined(separator: " · ")
    }

    @ViewBuilder
    private func depois(_ a: ResumoAgregado) -> some View {
        let ds = Array(a.depoisDoDesembarque.filter { $0.casos > 0 }.prefix(6))
        if !ds.isEmpty {
            Secao("Depois do desembarque", acao: { Text("nova corrida em 10 min").foregroundStyle(Tema.textoTerciario) }) {
                VStack(spacing: 0) {
                    ForEach(ds) { d in
                        linhaDado(nomes.rotulo(d.regiao),
                                  d.mediana.map { "espera típica " + Duracao.curta($0) } ?? "",
                                  "\(d.novaEmAte10) de \(d.casos)")
                        if d.id != ds.last?.id { Divisoria() }
                    }
                }
            }
        }
    }

    private func linhaDado(_ titulo: String, _ detalhe: String, _ valor: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Tipo.apoio.weight(.semibold))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                if !detalhe.isEmpty {
                    Text(detalhe)
                        .font(Tipo.legenda)
                        .monospacedDigit()
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            Spacer(minLength: Espaco.s)
            Text(valor)
                .font(Tipo.valor)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
        }
        .padding(.vertical, 10)
    }

    // MARK: Turnos

    private func turnosLista(_ lista: [Turno]) -> some View {
        Secao("Turnos") {
            VStack(spacing: 0) {
                ForEach(lista) { t in
                    NavigationLink { ResumoTurnoView(turno: t) } label: {
                        let r = turnos.resumo(t)
                        LinhaNavegacao(ResumoTurnoView.titulo(t), "flag",
                                       r.temLeitura ? Formato.reais(r.faturamentoConfirmado.valor ?? 0) : "—")
                    }
                    .buttonStyle(.plain)
                    if t.id != lista.last?.id { Divisoria() }
                }
            }
        }
    }
}

// MARK: - Por dia

struct ResumoDia: Identifiable {
    let dia: Date
    let resumos: [ResumoTurno]
    var id: Date { dia }
    var agregado: ResumoAgregado { ResumoAgregado(resumos: resumos) }
}

/// Barras por dia (só dias com turno: dia sem turno é hiato, não zero). Toque seleciona; começa no pico.
struct GraficoDias: View {
    let dias: [ResumoDia]
    @State private var selecionado: Date?

    private var pico: ResumoDia? { dias.max { $0.agregado.confirmado < $1.agregado.confirmado } }

    var body: some View {
        let atual = dias.first { $0.dia == selecionado } ?? pico
        VStack(alignment: .leading, spacing: Espaco.s) {
            Chart(dias) { d in
                BarMark(x: .value("Dia", d.dia, unit: .day), y: .value("R$", d.agregado.confirmado))
                    .foregroundStyle(Tema.positivo.opacity(d.dia == atual?.dia ? 1 : 0.3))
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: dias.count > 10 ? 5 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                        .foregroundStyle(Tema.textoTerciario)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Tema.linha)
                    AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n))") } }
                        .foregroundStyle(Tema.textoTerciario)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let area = geo[proxy.plotAreaFrame]
                    ZStack {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { ponto in
                                guard let alvo = proxy.value(atX: ponto.x - area.origin.x, as: Date.self) else { return }
                                selecionado = dias.min {
                                    abs($0.dia.addingTimeInterval(43_200).timeIntervalSince(alvo))
                                        < abs($1.dia.addingTimeInterval(43_200).timeIntervalSince(alvo))
                                }?.dia
                            }
                        if let d = atual, let x = proxy.position(forX: d.dia.addingTimeInterval(43_200)) {
                            PilulaSobreBarra(texto: Datas.curta(d.dia) + " • " + Formato.reais(d.agregado.confirmado),
                                             x: area.origin.x + x, largura: geo.size.width, topo: area.minY)
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding(.top, 34)
            .accessibilityLabel("Faturamento por dia")
            if let d = atual {
                DetalheGrafico(texto: Self.detalhe(d.agregado))
            }
        }
    }

    static func detalhe(_ a: ResumoAgregado) -> String {
        var p = [Datas.corridas(a.corridasConfirmadas), Duracao.curta(a.duracao)]
        if let km = a.km.valor { p.append(Formato.km(km)) }
        if let ph = a.porHora.valor { p.append(Formato.reais(ph) + "/h") }
        return p.joined(separator: " · ")
    }
}

/// Seg a dom: valor de cada dia da semana, ou "sem dados" quando não houve turno nele.
struct SemanaLista: View {
    let semana: [ResumoAgregado.DiaSemana]
    private static let ordem = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let maior = max(1, semana.map(\.faturamento).max() ?? 1)
        VStack(spacing: Espaco.s) {
            ForEach(Self.ordem, id: \.self) { n in
                let d = semana.first { $0.dia == n }
                HStack(spacing: Espaco.m) {
                    Text(Calendar.current.shortWeekdaySymbols[n - 1].replacingOccurrences(of: ".", with: "").capitalized)
                        .font(Tipo.legenda.weight(.semibold))
                        .foregroundStyle(Tema.textoSecundario)
                        .frame(width: 34, alignment: .leading)
                    if let d {
                        GeometryReader { g in
                            Capsule().fill(Tema.primaria.opacity(0.35))
                                .frame(width: max(4, g.size.width * d.faturamento / maior))
                        }
                        .frame(height: 8)
                        Text(Formato.reais(d.faturamento))
                            .font(Tipo.legenda.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Tema.texto)
                            .frame(width: 84, alignment: .trailing)
                    } else {
                        Text("sem dados")
                            .font(Tipo.legenda)
                            .foregroundStyle(Tema.textoTerciario)
                        Spacer()
                    }
                }
                .frame(minHeight: 18)
            }
        }
    }
}
