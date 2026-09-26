import SwiftUI
import Charts

struct AnalisesView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nomes = NomesRegioes.shared
    @State private var periodo: Periodo = .ultimos7

    var body: some View {
        let lista = Historico.turnos(turnos.turnos, em: periodo).sorted { $0.inicio > $1.inicio }
        let a = ResumoAgregado(resumos: lista.map { turnos.resumo($0) })
        let antes = ResumoAgregado(resumos: Historico.turnos(turnos.turnos, entre: periodo.anterior()).map { turnos.resumo($0) })

        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                FiltrosChips(opcoes: Periodo.allCases, nome: { $0.nome }, selecao: $periodo)
                    .padding(.horizontal, -Espaco.margem)

                if lista.isEmpty {
                    EstadoVazio(icone: "chart.bar", titulo: "Nenhum turno no período")
                } else {
                    topo(a, antes: antes)
                    indicadores(a)
                    porHora(a)
                    porDia(a)
                    if !a.tempoPorEstado.isEmpty {
                        Secao("Tempo") { BarraEstados(tempos: a.tempoPorEstado) }
                    }
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
            RotuloSecao("Faturamento")
            Text(Formato.reais(a.confirmado))
                .font(Tipo.destaque)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let d = Self.variacao(a.confirmado, antes.confirmado) {
                HStack(spacing: 4) {
                    Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.0f%% vs período anterior", d * 100))
                }
                .font(Tipo.legenda.weight(.semibold))
                .foregroundStyle(Tema.textoSecundario)
            }
        }
    }

    private static func variacao(_ agora: Double, _ antes: Double) -> Double? {
        antes > 0 ? (agora - antes) / antes : nil
    }

    private func indicadores(_ a: ResumoAgregado) -> some View {
        GradeMetricas {
            Metrica(a.porHora, "por hora") { Formato.reais($0) }
            Metrica(a.porKm, "por km") { Formato.reais($0) }
            Metrica(a.km, "km") { Formato.km($0) }
            Metrica(Duracao.curta(a.duracao), "de turno")
            Metrica("\(a.corridasConfirmadas)", a.corridasEstimadas > 0 ? "corridas · \(a.corridasEstimadas) ≈" : "corridas")
            Metrica("\(a.ofertasAceitas)/\(a.ofertas)", "ofertas aceitas")
            Metrica(Formato.reais(a.combustivel), "combustível")
            Metrica(a.resultado, "resultado") { Formato.reais($0) }
            Metrica("\(a.turnos)", a.turnos == 1 ? "turno" : "turnos")
        }
    }

    // MARK: Por hora e por dia

    @ViewBuilder
    private func porHora(_ a: ResumoAgregado) -> some View {
        let horas = a.horasDoDia
        if !horas.isEmpty {
            Secao("Por hora") {
                GraficoHoras(horas: horas)
                TabelaHoras(horas: horas)
            }
        }
    }

    private struct ValorDia: Identifiable {
        let dia: Date
        let valor: Double
        var id: Date { dia }
    }

    @ViewBuilder
    private func porDia(_ a: ResumoAgregado) -> some View {
        let dias = Dictionary(grouping: a.resumos) { Calendar.current.startOfDay(for: $0.turno.inicio) }
            .map { ValorDia(dia: $0.key, valor: $0.value.reduce(0) { $0 + ($1.faturamentoConfirmado.valor ?? 0) }) }
            .sorted { $0.dia < $1.dia }
        if dias.count > 1 {
            Secao("Por dia") {
                Chart(dias) { d in
                    BarMark(x: .value("Dia", d.dia, unit: .day), y: .value("R$", d.valor))
                        .foregroundStyle(Tema.primaria)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dias.count > 10 ? 5 : 1)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Tema.linha)
                        AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n))") } }
                    }
                }
                .frame(height: 150)

                let semana = a.diasDaSemana
                if semana.count > 1 {
                    let maior = max(1, semana.map(\.faturamento).max() ?? 1)
                    VStack(spacing: Espaco.s) {
                        ForEach(semana) { d in
                            HStack(spacing: Espaco.m) {
                                Text(d.nome.capitalized)
                                    .font(Tipo.legenda.weight(.semibold))
                                    .foregroundStyle(Tema.textoSecundario)
                                    .frame(width: 34, alignment: .leading)
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
                            }
                        }
                    }
                    .padding(.top, Espaco.s)
                }
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
                        LinhaNavegacao(ResumoTurnoView.titulo(t), "flag",
                                       Formato.reais(turnos.resumo(t).faturamentoConfirmado.valor ?? 0))
                    }
                    .buttonStyle(.plain)
                    if t.id != lista.last?.id { Divisoria() }
                }
            }
        }
    }
}
