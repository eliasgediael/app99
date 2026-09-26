import SwiftUI
import Charts

/// O dia é o dos turnos que começaram nele (igual a Viagens e Análises).
struct AtividadeView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nav = Navegacao.shared
    @State private var diaEscolhido: Date?
    @State private var mostrarOfertas = false

    var body: some View {
        let comRegistro = turnos.turnosComRegistro
        let dias = Array(Set(comRegistro.map { Calendar.current.startOfDay(for: $0.inicio) })).sorted(by: >)
        let dia = diaEscolhido.flatMap { d in dias.contains(d) ? d : nil } ?? dias.first
        let resumos = dia.map { d in
            comRegistro.filter { Calendar.current.isDate($0.inicio, inSameDayAs: d) }
                .sorted { $0.inicio < $1.inicio }
                .map { turnos.resumo($0) }
        } ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                if let dia {
                    cabecalho(dia, dias: dias, resumos: resumos)
                    let tempos = ResumoAgregado(resumos: resumos).tempoPorEstado
                    if resumos.contains(where: { $0.temLeitura }) && !tempos.isEmpty {
                        Secao("Tempo") { BarraEstados(tempos: tempos) }
                    }
                    let horas = Horas.porHora(resumos)
                    if !horas.isEmpty {
                        Secao("Por hora") {
                            GraficoHoras(horas: horas) { h in
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
                    EstadoVazio(icone: "clock", titulo: "Nenhum turno registrado")
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
        let comLeitura = resumos.contains { $0.temLeitura }
        let subtitulo = comLeitura ? Datas.corridas(a.corridasConfirmadas) + " · " + Duracao.curta(a.duracao)
                                   : Duracao.curta(a.duracao) + " sem leitura da tela"
        return HStack {
            Button { diaEscolhido = anterior } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 40, height: 40)
            }
            .disabled(i >= dias.count - 1)
            .accessibilityLabel("Dia anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(Datas.extensa(dia))
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
                Text(comLeitura ? Formato.reais(a.confirmado) : "—")
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

// MARK: - Gráficos

/// Linha logo abaixo do gráfico com os números do ponto selecionado.
struct DetalheGrafico: View {
    let texto: String
    var acao: (() -> Void)?

    var body: some View {
        HStack(spacing: Espaco.m) {
            Text(texto)
                .font(Tipo.legenda)
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
            Spacer(minLength: 0)
            if let acao {
                Button(action: acao) {
                    Image(systemName: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Tema.superficieAlta, in: Circle())
                        .foregroundStyle(Tema.primaria)
                }
                .accessibilityLabel("Ver no mapa")
            }
        }
        .frame(minHeight: 36)
    }
}

/// Posiciona a pílula sobre a barra selecionada, sem sair das bordas do gráfico.
struct PilulaSobreBarra: View {
    let texto: String
    let x: CGFloat
    let largura: CGFloat
    let topo: CGFloat

    var body: some View {
        let meia: CGFloat = 78
        Pilula(texto: texto)
            .position(x: min(max(x, meia), max(meia, largura - meia)), y: topo - 20)
            .allowsHitTesting(false)
    }
}

/// Barras por hora (confirmado + estimado empilhados). Toque seleciona; começa no pico.
struct GraficoHoras: View {
    let horas: [HoraAtividade]
    var aoAbrirMapa: ((HoraAtividade) -> Void)?
    @State private var selecionada: Date?

    private var pico: HoraAtividade? { horas.max { $0.confirmado < $1.confirmado } }

    var body: some View {
        let atual = horas.first { $0.inicio == selecionada } ?? pico
        VStack(alignment: .leading, spacing: Espaco.s) {
            if horas.contains(where: { $0.confirmado + $0.estimado > 0 }) {
                Chart {
                    ForEach(horas) { h in
                        BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.confirmado))
                            .foregroundStyle(Tema.positivo.opacity(h.inicio == atual?.inicio ? 1 : 0.3))
                            .cornerRadius(4)
                        BarMark(x: .value("Hora", h.inicio, unit: .hour), y: .value("R$", h.estimado))
                            .foregroundStyle(Tema.atencao.opacity(h.inicio == atual?.inicio ? 0.8 : 0.25))
                            .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: horas.count > 8 ? 3 : 1)) { _ in
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
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
                                    guard let d = proxy.value(atX: ponto.x - area.origin.x, as: Date.self) else { return }
                                    selecionada = horas.min {
                                        abs($0.inicio.addingTimeInterval(1800).timeIntervalSince(d))
                                            < abs($1.inicio.addingTimeInterval(1800).timeIntervalSince(d))
                                    }?.inicio
                                }
                            if let h = atual, let x = proxy.position(forX: h.inicio.addingTimeInterval(1800)) {
                                PilulaSobreBarra(texto: Self.pilula(h), x: area.origin.x + x,
                                                 largura: geo.size.width, topo: area.minY)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.top, 34)
                .accessibilityLabel("Faturamento por hora")
            }
            if let h = atual {
                DetalheGrafico(texto: Self.detalhe(h), acao: acaoMapa(h))
            }
        }
    }

    private func acaoMapa(_ h: HoraAtividade) -> (() -> Void)? {
        guard let abrir = aoAbrirMapa, h.comGPS, h.turno != nil else { return nil }
        return { abrir(h) }
    }

    static func pilula(_ h: HoraAtividade) -> String {
        h.intervaloTexto + " • " + (h.porHora.map { Formato.reais($0) + "/h" } ?? Formato.reais(h.confirmado))
    }

    static func detalhe(_ h: HoraAtividade) -> String {
        var p = [Formato.reais(h.confirmado), Datas.corridas(h.corridas)]
        if h.estimadas > 0 { p.append("\(h.estimadas) ≈") }
        if h.comGPS { p.append(Formato.km(h.km)) }
        if h.semCorrida >= 60 { p.append(Duracao.curta(h.semCorrida) + " sem corrida") }
        return p.joined(separator: " · ")
    }
}

// MARK: - Linha do tempo

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
