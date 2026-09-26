import SwiftUI
import Charts

/// Aba Atividade: a história do dia de trabalho.
/// Primeiro o dia por hora (gráfico + horas tocáveis → Mapa daquela hora), depois a narrativa.
/// O dia é o dos turnos que COMEÇARAM nele (igual a Viagens e Análises).
struct AtividadeView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nav = Navegacao.shared
    @State private var diaEscolhido: Date?
    @State private var filtro = FiltroAtividade.tudo

    /// Dias com turno (mais novo primeiro).
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
            VStack(alignment: .leading, spacing: Espaco.xl) {
                if let dia {
                    seletorDia(dia, dias: dias, resumos: resumos)
                    let horas = Horas.porHora(resumos)
                    if !horas.isEmpty { porHora(horas) }
                    narrativa(Narrativa.itens(resumos, eventos: linha.eventos))
                    NavigationLink {
                        LinhaDoTempoView(store: linha, intervalo: intervalo(resumos), titulo: "Linha do tempo técnica")
                    } label: {
                        LinhaNavegacao("Linha do tempo técnica", "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                } else {
                    EstadoVazio(icone: "clock", titulo: "Nenhum turno ainda",
                                texto: "Quando você rodar um turno, a história do dia aparece aqui: ofertas, corridas, esperas e o rendimento de cada hora.")
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Atividade")
        .refreshable { linha.pedir() }
    }

    private func intervalo(_ resumos: [ResumoTurno]) -> DateInterval? {
        guard let ini = resumos.map(\.turno.inicio).min() else { return nil }
        let fim = resumos.map { $0.turno.fim ?? Date() }.max() ?? Date()
        return DateInterval(start: ini, end: max(ini, fim))
    }

    // MARK: Dia

    private func seletorDia(_ dia: Date, dias: [Date], resumos: [ResumoTurno]) -> some View {
        let i = dias.firstIndex(of: dia) ?? 0
        let a = ResumoAgregado(resumos: resumos)
        return VStack(alignment: .leading, spacing: Espaco.s) {
            HStack {
                Button { diaEscolhido = dias[min(dias.count - 1, i + 1)] } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .disabled(i >= dias.count - 1)
                .accessibilityLabel("Dia anterior")
                Spacer()
                Text(Datas.curta(dia).capitalized)
                    .font(Tipo.titulo)
                    .foregroundStyle(Tema.texto)
                Spacer()
                Button { diaEscolhido = dias[max(0, i - 1)] } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(i == 0)
                .accessibilityLabel("Próximo dia")
            }
            .foregroundStyle(Tema.primaria)
            Text("\(Formato.reais(a.confirmado)) confirmado · " + PainelTurno.corridas(a.corridasConfirmadas)
                 + (a.km.valor.map { " · " + Formato.km($0) } ?? "") + " · " + Duracao.curta(a.duracao) + " de turno")
                .font(Tipo.apoio)
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Por hora

    private func porHora(_ horas: [HoraAtividade]) -> some View {
        Bloco("Por hora", subtitulo: "cada corrida conta na hora em que terminou") {
            GraficoHoras(horas: horas)
            VStack(spacing: 0) {
                ForEach(horas) { h in
                    Button {
                        if let t = h.turno {
                            nav.abrirMapa(turno: t, intervalo: DateInterval(start: h.inicio, duration: 3600))
                        }
                    } label: {
                        LinhaHora(h: h, mostraSeta: h.turno != nil && h.comGPS)
                    }
                    .buttonStyle(.plain)
                    .disabled(!h.comGPS)
                    if h.id != horas.last?.id { Divisoria() }
                }
            }
        }
    }

    // MARK: Narrativa

    private func narrativa(_ todos: [ItemAtividade]) -> some View {
        let itens = filtro == .tudo ? todos : todos.filter { $0.categoria == filtro }
        return Bloco("Linha do tempo") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espaco.s) {
                    ForEach(FiltroAtividade.allCases) { f in
                        ChipFiltro(titulo: f.nome, ativo: filtro == f) { filtro = f }
                    }
                }
            }
            if itens.isEmpty {
                Text("Nada deste tipo neste dia.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(itens) { item in
                    if let c = item.corrida, let r = item.resumo {
                        NavigationLink { CorridaDetalheView(c: c, r: r) } label: { LinhaNarrativa(item: item, seta: true) }
                            .buttonStyle(.plain)
                    } else {
                        LinhaNarrativa(item: item, seta: false)
                    }
                }
            }
        }
    }
}

// MARK: - Peças

/// Gráfico de barras por hora: confirmado (menta) e estimado (âmbar) empilhados.
struct GraficoHoras: View {
    let horas: [HoraAtividade]
    var porHoraDoDia = false

    var body: some View {
        Chart {
            ForEach(horas) { h in
                BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.confirmado))
                    .foregroundStyle(Tema.positivo)
                BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.estimado))
                    .foregroundStyle(Tema.atencao.opacity(0.7))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: horas.count > 8 ? 3 : 1)) { _ in
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                AxisGridLine().foregroundStyle(Tema.linha)
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisValueLabel { if let n = v.as(Double.self) { Text("R$ \(Int(n))") } }
                AxisGridLine().foregroundStyle(Tema.linha)
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Faturamento por hora")
    }
}

/// "21–22   R$ 27,60 · 4 corridas · 19 km · 6 min sem corrida"
struct LinhaHora: View {
    let h: HoraAtividade
    var mostraSeta = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(h.rotulo)
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Formato.reais(h.confirmado))
                        .font(Tipo.corpo.weight(.semibold))
                        .foregroundStyle(Tema.texto)
                    if h.estimado > 0 {
                        Text("+ ≈ " + Formato.reais(h.estimado))
                            .font(Tipo.legenda)
                            .foregroundStyle(Tema.atencao)
                    }
                }
                .monospacedDigit()
                Text(detalhes)
                    .font(Tipo.legenda)
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
            }
            Spacer(minLength: 0)
            if mostraSeta {
                Image(systemName: "map").font(.caption).foregroundStyle(Tema.textoTerciario)
            }
        }
        .padding(.vertical, Espaco.s)
        .contentShape(Rectangle())
    }

    private var detalhes: String {
        var p = [PainelTurno.corridas(h.corridas)]
        if h.comGPS { p.append(Formato.km(h.km)) }
        if h.semCorrida >= 60 { p.append(Duracao.curta(h.semCorrida) + " sem corrida") }
        if let ph = h.porHora { p.append(Formato.reais(ph) + "/h") }
        return p.joined(separator: " · ")
    }
}

/// Uma linha da narrativa: hora, ícone colorido pelo tipo, título e detalhe.
struct LinhaNarrativa: View {
    let item: ItemAtividade
    let seta: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Espaco.m) {
            Text(PainelTurno.hora(item.em))
                .font(Tipo.legenda.monospacedDigit())
                .foregroundStyle(Tema.textoTerciario)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)
            Image(systemName: item.icone)
                .font(item.discreto ? .caption : .subheadline)
                .foregroundStyle(item.cor)
                .frame(width: 20)
                .padding(.top, item.discreto ? 3 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.titulo)
                    .font(item.discreto ? Tipo.legenda : Tipo.apoio.weight(.semibold))
                    .foregroundStyle(item.discreto ? Tema.textoSecundario : Tema.texto)
                if let d = item.detalhe, !d.isEmpty {
                    Text(d)
                        .font(Tipo.legenda)
                        .monospacedDigit()
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            Spacer(minLength: 0)
            if seta {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Tema.textoTerciario)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, item.discreto ? 5 : 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
