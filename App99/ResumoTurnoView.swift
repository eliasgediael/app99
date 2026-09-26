import SwiftUI

/// Resumo de um turno: primeiro quanto rendeu, depois o ritmo e o tempo; cada parte abre numa tela própria.
struct ResumoTurnoView: View {
    let turno: Turno
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @Environment(\.dismiss) private var fechar

    var body: some View {
        conteudo(turnos.resumo(turno))
            .navigationTitle("Resumo do turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { fechar() } }
    }

    private func conteudo(_ r: ResumoTurno) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                principais(r)
                ritmo(r)
                avisos(r)
                Bloco("Onde foi o tempo") {
                    if r.tempoPorEstado.isEmpty {
                        Text("Sem dados de tempo neste turno.").font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
                    } else {
                        BarraEstados(tempos: r.tempoPorEstado)
                    }
                }
                Bloco("Detalhes") { partes(r) }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
    }

    private func principais(_ r: ResumoTurno) -> some View {
        VStack(alignment: .leading, spacing: Espaco.xs) {
            RotuloSecao(Self.titulo(turno))
            Text(Formato.reais(r.faturamentoConfirmado.valor ?? 0))
                .font(Tipo.destaque)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("faturamento confirmado · " + PainelTurno.corridas(r.corridasConfirmadas))
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
            HStack(spacing: 4) {
                Text("Após custos registrados:")
                MedidaTexto(medida: r.resultado) { Formato.reais($0) }
            }
            .font(Tipo.apoio)
            .foregroundStyle(Tema.textoSecundario)
            .padding(.top, 2)
        }
    }

    private func ritmo(_ r: ResumoTurno) -> some View {
        HStack(alignment: .top, spacing: Espaco.m) {
            MetricaCompacta(r.porHora, rotulo: "por hora") { Formato.reais($0) }
            MetricaCompacta(r.porKm, rotulo: "por km") { Formato.reais($0) }
            MetricaCompacta(r.km, rotulo: "rodados") { Formato.km($0) }
            MetricaCompacta(valor: Duracao.curta(r.duracao.valor ?? 0), rotulo: "de turno")
        }
    }

    @ViewBuilder
    private func avisos(_ r: ResumoTurno) -> some View {
        if r.corridasEstimadas > 0 || r.corridasIndeterminadas > 0 || (r.temGPS && r.tempoSemSinalGPS >= 60) {
            VStack(spacing: Espaco.s) {
                if r.corridasEstimadas > 0 {
                    let n = r.corridasEstimadas
                    Aviso(.estimativa, n == 1 ? "1 corrida não pôde ser confirmada" : "\(n) corridas não puderam ser confirmadas",
                          impacto: "≈ \(Formato.reais(r.faturamentoEstimado.valor ?? 0)) ficou fora do faturamento confirmado.")
                }
                if r.corridasIndeterminadas > 0 {
                    let n = r.corridasIndeterminadas
                    Aviso(.informacao, n == 1 ? "1 corrida sem valor identificado" : "\(n) corridas sem valor identificado",
                          impacto: "Não entram em nenhum total. Toque em Corridas pra ver o motivo de cada uma.")
                }
                if r.temGPS && r.tempoSemSinalGPS >= 60 {
                    Aviso(.atencao, "GPS sem sinal por \(Duracao.curta(r.tempoSemSinalGPS))",
                          impacto: "Os km desse tempo não foram somados; km e R$/km aparecem como estimados.")
                }
            }
        }
    }

    private func partes(_ r: ResumoTurno) -> some View {
        VStack(spacing: 0) {
            NavigationLink { FinanceiroView(r: r) } label: {
                LinhaNavegacao("Financeiro", "dollarsign.circle", Formato.reais(r.faturamentoConfirmado.valor ?? 0))
            }
            Divisoria()
            NavigationLink { CorridasView(r: r) } label: {
                LinhaNavegacao("Corridas", "car", "\(r.corridasFeitas)" + (r.corridasEstimadas > 0 ? " · \(r.corridasEstimadas) ≈" : ""))
            }
            Divisoria()
            NavigationLink { OfertasView(r: r) } label: {
                LinhaNavegacao("Ofertas", "tag", "\(r.ofertas.count)")
            }
            if r.temGPS {
                Divisoria()
                Button { Navegacao.shared.abrirMapa(turno: turno.id) } label: {
                    LinhaNavegacao("Mapa", "map", r.km.valor.map(Formato.km) ?? "")
                }
            }
            Divisoria()
            NavigationLink { TempoView(r: r) } label: {
                LinhaNavegacao("Tempo", "clock", Duracao.curta(r.duracao.valor ?? 0))
            }
            Divisoria()
            NavigationLink { DistanciaView(r: r) } label: {
                LinhaNavegacao("Distância", "road.lanes", r.km.valor.map(Formato.km) ?? "—")
            }
            Divisoria()
            NavigationLink { CustosView(r: r) } label: {
                LinhaNavegacao("Abastecimentos e custos", "fuelpump", r.custos.isEmpty ? "" : "\(r.custos.count)")
            }
            Divisoria()
            NavigationLink {
                LinhaDoTempoView(store: linha, intervalo: DateInterval(start: turno.inicio, end: turno.fim ?? Date()))
            } label: {
                LinhaNavegacao("Linha do tempo técnica", "list.bullet.rectangle")
            }
        }
        .buttonStyle(.plain)
    }

    static func titulo(_ t: Turno) -> String {
        let hora = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        return "\(Datas.curta(t.inicio)) · \(hora(t.inicio))–\(t.fim.map(hora) ?? "agora")"
    }
}

// MARK: - Peças reutilizadas nas telas de resumo

/// Linha "título ........ valor" com a confiança discreta (≈ / —) e detalhe ao tocar.
struct Campo: View {
    let titulo: String
    let medida: Medida
    let formatar: (Double) -> String

    init(_ titulo: String, _ medida: Medida, formatar: @escaping (Double) -> String) {
        self.titulo = titulo
        self.medida = medida
        self.formatar = formatar
    }

    var body: some View {
        LabeledContent(titulo) { MedidaTexto(medida: medida, formatar: formatar) }
    }
}

// MARK: - Financeiro

private struct FinanceiroView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section("Faturamento") {
                Campo("Confirmado", r.faturamentoConfirmado) { Formato.reais($0) }
                Campo("Estimado (fora do total)", r.faturamentoEstimado) { Formato.reais($0) }
                Campo("Média por corrida confirmada", r.mediaPorCorrida) { Formato.reais($0) }
            }
            Section("Custos") {
                Campo("Abastecimentos", r.combustivel) { Formato.reais($0) }
                Campo("Outros custos", r.outrosCustos) { Formato.reais($0) }
                Campo("Custo estimado (custo/km × km)", r.custoEstimadoPorKm) { Formato.reais($0) }
                Campo("Combustível por km", r.combustivelPorKm) { Formato.reais($0) }
            }
            Section {
                Campo("Após custos registrados", r.resultado) { Formato.reais($0) }
                Campo("Após custo/km dos Ajustes", r.resultadoEstimado) { Formato.reais($0) }
            } header: {
                Text("Resultado")
            } footer: {
                Text("Abastecimento é o que você colocou no tanque, não o que gastou neste turno; por isso o resultado aparece como estimado. Em vários turnos a média fica precisa.")
            }
            Section("Por tempo e distância") {
                Campo("R$/hora", r.porHora) { Formato.reais($0) }
                Campo("R$/hora ativo (sem pausas)", r.porHoraAtivo) { Formato.reais($0) }
                Campo("R$/km", r.porKm) { Formato.reais($0) }
            }
        }
        .navigationTitle("Financeiro")
    }
}

// MARK: - Distância

private struct DistanciaView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                Campo("Total", r.km) { Formato.km($0) }
                ForEach([EstadoMotorista.emCorrida, .aCaminho, .aguardando, .pausado, .semLeitura], id: \.self) { e in
                    if let km = r.kmPorEstado[e], km >= 0.05 {
                        LabeledContent(e.nome, value: Formato.km(km))
                    }
                }
                if r.tempoSemSinalGPS >= 60 {
                    LabeledContent("Sem sinal (não somado)", value: Duracao.curta(r.tempoSemSinalGPS))
                }
            } footer: {
                Text(r.temGPS
                     ? "Distância do GPS filtrado: tremidas parado, saltos impossíveis e pontos imprecisos ficam de fora; trechos sem sinal não são ligados em linha reta."
                     : "Sem GPS neste turno.")
            }
        }
        .navigationTitle("Distância")
    }
}

// MARK: - Tempo

private struct TempoView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                LabeledContent("Duração do turno", value: Duracao.curta(r.duracao.valor ?? 0))
                Campo("Ativo (sem pausas)", r.tempoAtivo) { Duracao.curta($0) }
                ForEach(EstadoMotorista.allCases, id: \.self) { e in
                    if let s = r.tempoPorEstado[e], s >= 60 {
                        LabeledContent(e.nome) {
                            Text(Duracao.curta(s) + (r.percentual(e).map { String(format: "  %.0f%%", $0 * 100) } ?? ""))
                                .monospacedDigit()
                        }
                    }
                }
                Campo("Parado (GPS)", r.tempoParado) { Duracao.curta($0) }
            } footer: {
                Text("\"Sem leitura\" = a leitura da tela estava desligada: não dá pra saber o que aconteceu nesse tempo.")
            }
        }
        .navigationTitle("Tempo")
    }
}

// MARK: - Corridas

private struct CorridasView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            if r.corridas.isEmpty {
                Text("Nenhuma corrida detectada neste turno.").foregroundStyle(.secondary)
            }
            ForEach(r.corridas.reversed()) { c in
                NavigationLink { CorridaDetalheView(c: c, r: r) } label: { LinhaCorrida(c: c) }
            }
        }
        .navigationTitle("Corridas")
    }
}

// MARK: - Ofertas

private struct OfertasView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                LabeledContent("Recebidas", value: "\(r.ofertas.count)")
                LabeledContent("Aceitas", value: "\(r.ofertas.filter { $0.resultado == .aceita }.count)")
                LabeledContent("Não aceitas (recusou ou expirou)", value: "\(r.ofertas.filter { $0.resultado == .naoAceita }.count)")
            } footer: {
                Text("A tela não mostra se a oferta foi recusada ou só expirou; as duas contam como \"não aceita\".")
            }
            Section {
                ForEach(r.ofertas.reversed()) { o in
                    LinhaOferta(o: o)
                }
            }
        }
        .navigationTitle("Ofertas")
    }
}

// MARK: - Custos

private struct CustosView: View {
    let r: ResumoTurno
    @State private var novo = false

    var body: some View {
        List {
            if r.custos.isEmpty {
                Text("Nenhum custo registrado neste turno.").foregroundStyle(.secondary)
            }
            ForEach(r.custos) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.resumo)
                    Text(([c.em.formatted(date: .omitted, time: .shortened), c.precoLitro.map { String(format: "R$ %.3f/L", $0).replacingOccurrences(of: ".", with: ",") }, c.posto, c.observacao] as [String?])
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { novo = true } label: { Label("Abastecimento", systemImage: "plus") }
        }
        .navigationTitle("Abastecimentos e custos")
        .sheet(isPresented: $novo) { NavigationStack { AbastecimentoView() } }
    }
}
