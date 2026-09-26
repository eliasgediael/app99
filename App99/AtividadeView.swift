import SwiftUI
import Charts

/// O dia é o dos turnos que começaram nele (igual a Viagens e Análises).
struct AtividadeView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nav = Navegacao.shared
    @State private var diaEscolhido: Date?
    @State private var mostrarOfertas = false

    private var dias: [Date] {
        Array(Set(turnos.turnos.map { Calendar.current.startOfDay(for: $0.inicio) })).sorted(by: >)
    }

    var body: some View {
        let dias = self.dias
        let dia = diaEscolhido.flatMap { d in dias.contains(d) ? d : nil } ?? dias.first
        let resumos = dia.map { d in
            turnos.turnos.filter { Calendar.current.isDate($0.inicio, inSameDayAs: d) }
                .sorted { $0.inicio < $1.inicio }
                .map { turnos.resumo($0) }
        } ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                if let dia {
                    cabecalho(dia, dias: dias, resumos: resumos)
                    let horas = Horas.porHora(resumos)
                    if !horas.isEmpty {
                        Secao("Por hora") {
                            GraficoHoras(horas: horas)
                            TabelaHoras(horas: horas) { h in
                                if let t = h.turno {
                                    nav.abrirMapa(turno: t, intervalo: DateInterval(start: h.inicio, duration: 3600))
                                }
                            }
                        }
                    }
                    Secao("Linha do tempo", acao: {
                        Button(mostrarOfertas ? "Ocultar ofertas" : "Mostrar ofertas") { mostrarOfertas.toggle() }
                    }) {
                        LinhaDoTempoVisual(itens: Narrativa.itens(resumos, eventos: linha.eventos, ofertas: mostrarOfertas))
                    }
                } else {
                    EstadoVazio(icone: "clock", titulo: "Nenhum turno ainda")
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Atividade")
        .refreshable { linha.pedir() }
    }

    private func cabecalho(_ dia: Date, dias: [Date], resumos: [ResumoTurno]) -> some View {
        let i = dias.firstIndex(of: dia) ?? 0
        let anterior = dias[min(dias.count - 1, i + 1)]
        let proximo = dias[max(0, i - 1)]
        let a = ResumoAgregado(resumos: resumos)
        let subtitulo = Datas.corridas(a.corridasConfirmadas) + " · " + Duracao.curta(a.duracao)
        return HStack {
            Button { diaEscolhido = anterior } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 40, height: 40)
            }
            .disabled(i >= dias.count - 1)
            .accessibilityLabel("Dia anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(Datas.longa(dia).capitalized)
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
                Text(Formato.reais(a.confirmado))
                    .font(Tipo.destaque)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                Text(subtitulo)
                    .font(Tipo.legenda)
                    .foregroundStyle(Tema.textoSecundario)
            }
            Spacer()
            Button { diaEscolhido = proximo } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 40, height: 40)
            }
            .disabled(i == 0)
            .accessibilityLabel("Próximo dia")
        }
        .foregroundStyle(Tema.primaria)
    }
}

// MARK: - Peças

/// Barras por hora: confirmado (menta) + estimado (âmbar) empilhados.
struct GraficoHoras: View {
    let horas: [HoraAtividade]

    var body: some View {
        Chart {
            ForEach(horas) { h in
                BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.confirmado))
                    .foregroundStyle(Tema.positivo)
                    .cornerRadius(3)
                BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.estimado))
                    .foregroundStyle(Tema.atencao.opacity(0.7))
                    .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: horas.count > 8 ? 3 : 1)) { _ in
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Tema.linha)
                AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n))") } }
            }
        }
        .frame(height: 160)
        .accessibilityLabel("Faturamento por hora")
    }
}

struct TabelaHoras: View {
    let horas: [HoraAtividade]
    var aoTocar: ((HoraAtividade) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(horas) { h in
                Button { aoTocar?(h) } label: { linha(h) }
                    .buttonStyle(.plain)
                    .disabled(aoTocar == nil || !h.comGPS)
                if h.id != horas.last?.id { Divisoria() }
            }
        }
    }

    private func linha(_ h: HoraAtividade) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(h.rotulo)
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(Formato.reais(h.confirmado))
                    .font(Tipo.valor)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                Text(detalhe(h))
                    .font(Tipo.legenda)
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
            }
            Spacer(minLength: Espaco.s)
            if let ph = h.porHora {
                Text(Formato.reais(ph) + "/h")
                    .font(Tipo.legenda.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func detalhe(_ h: HoraAtividade) -> String {
        var p = [Datas.corridas(h.corridas)]
        if h.comGPS { p.append(Formato.km(h.km)) }
        if h.semCorrida >= 60 { p.append(Duracao.curta(h.semCorrida) + " livre") }
        return p.joined(separator: " · ")
    }
}

struct LinhaDoTempoVisual: View {
    let itens: [ItemAtividade]

    var body: some View {
        if itens.isEmpty {
            EstadoVazio(icone: "clock", titulo: "Sem registros")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(itens) { item in
                    if let c = item.corrida, let r = item.resumo {
                        NavigationLink { CorridaDetalheView(c: c, r: r) } label: {
                            linha(item, ultima: item.id == itens.last?.id)
                        }
                        .buttonStyle(.plain)
                    } else {
                        linha(item, ultima: item.id == itens.last?.id)
                    }
                }
            }
        }
    }

    private func linha(_ item: ItemAtividade, ultima: Bool) -> some View {
        let forte = item.tipo == .corrida || item.tipo == .turno
        let fonte: Font = item.tipo == .corrida ? Tipo.valor : (forte ? Tipo.apoio.weight(.semibold) : Tipo.apoio)
        let corTitulo: Color
        if item.tipo == .corrida {
            corTitulo = item.corrida?.estimada == true ? Tema.atencao : Tema.texto
        } else {
            corTitulo = forte ? Tema.texto : Tema.textoSecundario
        }
        return HStack(alignment: .top, spacing: Espaco.m) {
            Text(Datas.hora(item.em))
                .font(Tipo.legenda.monospacedDigit())
                .foregroundStyle(Tema.textoTerciario)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Circle()
                    .fill(item.cor)
                    .frame(width: forte ? 10 : 7, height: forte ? 10 : 7)
                    .padding(.top, forte ? 4 : 6)
                if !ultima {
                    Rectangle().fill(Tema.linha).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.titulo)
                    .font(fonte)
                    .monospacedDigit()
                    .foregroundStyle(corTitulo)
                if let d = item.detalhe {
                    Text(d)
                        .font(Tipo.legenda)
                        .monospacedDigit()
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            .padding(.bottom, Espaco.m)
            Spacer(minLength: 0)
            if item.corrida != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Tema.textoTerciario)
                    .padding(.top, 5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
