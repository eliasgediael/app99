import SwiftUI

/// Aba Turno: painel de operação.
/// Sem turno → iniciar. Com turno, nesta ordem: o que está acontecendo, quanto fiz, ritmo,
/// a última corrida, avisos (só quando existem) e as ações. Detalhes ficam no resumo.
struct PainelTurno: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var monitor: MonitorExtensao
    @ObservedObject var gps = Localizacao.shared
    @ObservedObject var nav = Navegacao.shared
    @AppStorage("metaDiaria") private var metaDiaria = 0.0

    @State private var seletor = SeletorTransmissao()
    @State private var confirmarEncerrar = false
    @State private var resumoAberto: Turno?
    @State private var abastecendo = false

    var body: some View {
        ScrollView {
            Group {
                if let t = turnos.atual {
                    TimelineView(.periodic(from: .now, by: 30)) { contexto in
                        painel(t, resumo: turnos.resumo(t, agora: contexto.date), agora: contexto.date)
                    }
                } else {
                    semTurno
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.s)
            .padding(.bottom, Espaco.xl)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .background(SeletorView(picker: seletor.picker).frame(width: 1, height: 1).opacity(0.01))
        .sheet(item: $resumoAberto) { t in
            NavigationStack { ResumoTurnoView(turno: t) }
        }
        .sheet(isPresented: $abastecendo) {
            NavigationStack { AbastecimentoView() }
        }
        .onChange(of: nav.aba) { _ in resumoAberto = nil }   // "ver no mapa" de dentro do resumo
    }

    // MARK: Sem turno

    private var semTurno: some View {
        VStack(alignment: .leading, spacing: Espaco.xl) {
            VStack(alignment: .leading, spacing: Espaco.s) {
                PontoEstado(texto: "Sem turno", cor: Tema.textoTerciario)
                Text("Turno não iniciado")
                    .font(.title.bold())
                    .foregroundStyle(Tema.texto)
                Text("Ao iniciar, o Apex liga a leitura da tela e o GPS e passa a medir faturamento, km e tempo.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
            }

            VStack(spacing: Espaco.m) {
                Button {
                    turnos.iniciar()
                    seletor.abrir()   // o iOS ainda pede o toque em "Iniciar Transmissão"
                } label: {
                    Label("Iniciar turno", systemImage: "play.fill")
                }
                .buttonStyle(BotaoPrimario())
                Button { abastecendo = true } label: {
                    Label("Registrar abastecimento", systemImage: "fuelpump")
                }
                .buttonStyle(BotaoSecundario())
            }

            if metaDiaria > 0 {
                Bloco("Meta do dia") { BarraMeta(valor: confirmadoHoje, meta: metaDiaria) }
            }

            if let u = turnos.ultimoEncerrado {
                let r = turnos.resumo(u)
                NavigationLink { ResumoTurnoView(turno: u) } label: {
                    Bloco("Último turno") {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: Espaco.xs) {
                                Text(Formato.reais(r.faturamentoConfirmado.valor ?? 0))
                                    .font(Tipo.metrica)
                                    .monospacedDigit()
                                    .foregroundStyle(Tema.texto)
                                Text("\(ResumoTurnoView.titulo(u)) · \(Duracao.curta(r.duracao.valor ?? 0))")
                                    .font(Tipo.legenda)
                                    .foregroundStyle(Tema.textoSecundario)
                                Text(([Self.corridas(r.corridasConfirmadas),
                                       r.porHora.valor.map { Formato.reais($0) + "/h" }] as [String?])
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(Tipo.legenda)
                                    .foregroundStyle(Tema.textoSecundario)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Tema.textoTerciario)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Turno ativo

    private func painel(_ t: Turno, resumo r: ResumoTurno, agora: Date) -> some View {
        let estado = t.pausadoAgora ? EstadoMotorista.pausado : (r.segmentos.last?.estado ?? .semLeitura)
        let desde = r.segmentos.last?.inicio ?? t.inicio
        let avisos = avisos(r)

        return VStack(alignment: .leading, spacing: Espaco.xl) {
            // 1. O que está acontecendo
            HStack {
                PontoEstado(texto: "\(estado.nome) · há \(Duracao.curta(agora.timeIntervalSince(desde)))", cor: estado.cor)
                Spacer()
                indicador("Leitura", ligado: monitor.ligada)
                indicador("GPS", ligado: gps.estado == .ativo)
            }

            // 2. Quanto fiz
            VStack(alignment: .leading, spacing: Espaco.xs) {
                Text(Formato.reais(r.faturamentoConfirmado.valor ?? 0))
                    .font(Tipo.destaque)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("faturamento confirmado · " + Self.corridas(r.corridasConfirmadas))
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
                if metaDiaria > 0 {
                    BarraMeta(valor: confirmadoHoje, meta: metaDiaria).padding(.top, Espaco.s)
                }
            }

            // 3. Ritmo
            HStack(alignment: .top, spacing: Espaco.m) {
                MetricaCompacta(r.porHora, rotulo: "por hora") { Formato.reais($0) }
                MetricaCompacta(r.porKm, rotulo: "por km") { Formato.reais($0) }
                MetricaCompacta(r.km, rotulo: "rodados") { Formato.km($0) }
                MetricaCompacta(valor: Duracao.curta(r.duracao.valor ?? 0), rotulo: "de turno")
            }

            // 4. Agora e a última corrida
            corridaAtual(r)

            // 5. Avisos (só quando existem)
            if !avisos.isEmpty {
                VStack(spacing: Espaco.s) {
                    ForEach(avisos.indices, id: \.self) { avisos[$0] }
                }
            }

            // 6. Ações
            VStack(spacing: Espaco.m) {
                HStack(spacing: Espaco.m) {
                    Button {
                        t.pausadoAgora ? turnos.retomar() : turnos.pausar()
                    } label: {
                        Label(t.pausadoAgora ? "Retomar" : "Pausar", systemImage: t.pausadoAgora ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(BotaoSecundario())
                    Button { abastecendo = true } label: {
                        Label("Abastecer", systemImage: "fuelpump")
                    }
                    .buttonStyle(BotaoSecundario())
                }
                HStack {
                    Button("Encerrar turno", role: .destructive) { confirmarEncerrar = true }
                        .font(.headline)
                        .foregroundStyle(Tema.erro)
                    Spacer()
                    NavigationLink { ResumoTurnoView(turno: t) } label: {
                        HStack(spacing: 4) {
                            Text("Resumo do turno")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(Tipo.apoio.weight(.medium))
                        .foregroundStyle(Tema.primaria)
                    }
                }
                .padding(.top, Espaco.xs)
                .confirmationDialog("Encerrar o turno?", isPresented: $confirmarEncerrar, titleVisibility: .visible) {
                    Button("Encerrar turno", role: .destructive) {
                        SinalApp.encerrarLeitura.enviar()
                        resumoAberto = turnos.encerrar()
                    }
                } message: {
                    Text("A leitura da tela e o GPS param, e o resumo do turno abre em seguida.")
                }
            }
        }
    }

    /// Corrida em andamento (valor ainda não confirmado) e a última corrida encerrada.
    @ViewBuilder
    private func corridaAtual(_ r: ResumoTurno) -> some View {
        let aberta = r.corridas.last { $0.confianca == nil && $0.estado != .cancelada }
        let ultima = r.corridas.last { $0.confianca != nil && $0.estado != .cancelada }
        if aberta != nil || ultima != nil {
            Bloco {
                VStack(alignment: .leading, spacing: Espaco.m) {
                    if let c = aberta {
                        VStack(alignment: .leading, spacing: 2) {
                            RotuloSecao(c.aBordoEm == nil ? "Indo buscar" : "Em corrida")
                            Text(([c.aceiteEm.map { "aceita às " + Self.hora($0) },
                                   c.valorOfertaCent.map { "oferta de " + Formato.reais(Double($0) / 100) + " · a confirmar" }] as [String?])
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(Tipo.apoio)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        if ultima != nil { Divisoria() }
                    }
                    if let c = ultima {
                        VStack(alignment: .leading, spacing: Espaco.xs) {
                            RotuloSecao("Última corrida")
                            NavigationLink { CorridaDetalheView(c: c, r: r) } label: {
                                LinhaCorrida(c: c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Cada aviso diz o que aconteceu, se mexe em algum número e o que fazer.
    private func avisos(_ r: ResumoTurno) -> [Aviso] {
        var lista: [Aviso] = []
        switch gps.estado {
        case .semPermissao:
            lista.append(Aviso(.problema, "Sem permissão de localização",
                               impacto: "Km, R$/km e o mapa ficam em branco neste turno.",
                               acaoTitulo: "Abrir Ajustes do iPhone") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        case .semSinal:
            lista.append(Aviso(.atencao, "GPS sem sinal",
                               impacto: "Os km deste trecho não entram na conta. Não precisa fazer nada."))
        default: break
        }
        if !monitor.ligada {
            lista.append(Aviso(.atencao, "Sem sinal da leitura da tela",
                               impacto: "Se ela estiver desligada, ofertas e corridas deste período não são registradas.",
                               acaoTitulo: "Ligar leitura") { seletor.abrir() })
        }
        if r.corridasEstimadas > 0 {
            let n = r.corridasEstimadas
            lista.append(Aviso(.estimativa,
                               n == 1 ? "1 corrida ainda não pôde ser confirmada" : "\(n) corridas ainda não puderam ser confirmadas",
                               impacto: "≈ \(Formato.reais(r.faturamentoEstimado.valor ?? 0)) fica fora do faturamento confirmado."))
        }
        if r.corridasIndeterminadas > 0 {
            let n = r.corridasIndeterminadas
            lista.append(Aviso(.informacao,
                               n == 1 ? "1 corrida sem valor identificado" : "\(n) corridas sem valor identificado",
                               impacto: "Não entram em nenhum total. O motivo está no detalhe de cada uma, em Viagens."))
        }
        return lista
    }

    /// Faturamento confirmado dos turnos de hoje (inclui o ativo, mesmo que tenha começado ontem).
    private var confirmadoHoje: Double {
        var lista = Historico.turnos(turnos.turnos, em: .hoje)
        if let a = turnos.atual, !lista.contains(where: { $0.id == a.id }) { lista.append(a) }
        return lista.reduce(0) { $0 + (turnos.resumo($1).faturamentoConfirmado.valor ?? 0) }
    }

    private func indicador(_ nome: String, ligado: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ligado ? Tema.positivo : Tema.textoTerciario).frame(width: 7, height: 7)
            Text(nome).font(.caption2).foregroundStyle(Tema.textoSecundario)
        }
        .accessibilityLabel("\(nome) \(ligado ? "ligado" : "desligado")")
    }

    static func corridas(_ n: Int) -> String {
        n == 1 ? "1 corrida" : "\(n) corridas"
    }

    static func hora(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Abastecimento

/// Registro rápido: valor + preço/L → litros calculados (ou litros direto).
struct AbastecimentoView: View {
    @Environment(\.dismiss) private var fechar

    @State private var valor: Double?
    @State private var precoLitro: Double? = {
        let padrao = UserDefaults.standard.double(forKey: "precoLitroPadrao")
        return padrao > 0 ? padrao : nil
    }()
    @State private var informarLitros = false
    @State private var litrosDigitados: Double?
    @State private var em = Date()
    @State private var posto = ""
    @State private var observacao = ""

    private let formatoReais = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR"))
    private let formatoPreco = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3)).locale(Locale(identifier: "pt_BR"))

    private var litros: Double? {
        if informarLitros { return litrosDigitados }
        guard let v = valor, let p = precoLitro, p > 0 else { return nil }
        return v / p
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Valor pago (R$)") {
                    TextField("20,00", value: $valor, format: formatoReais)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Preço por litro (R$)") {
                    TextField("6,290", value: $precoLitro, format: formatoPreco)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Toggle("Informar litros direto", isOn: $informarLitros)
                if informarLitros {
                    LabeledContent("Litros") {
                        TextField("3,18", value: $litrosDigitados, format: formatoReais)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } else {
                    LabeledContent("Litros", value: litros.map { String(format: "%.2f L", $0).replacingOccurrences(of: ".", with: ",") } ?? "—")
                }
            }
            Section {
                DatePicker("Quando", selection: $em)
                TextField("Posto (opcional)", text: $posto)
                TextField("Observação (opcional)", text: $observacao)
            }
        }
        .navigationTitle("Abastecimento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { fechar() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { salvar() }.disabled((valor ?? 0) <= 0)
            }
        }
    }

    private func salvar() {
        guard let v = valor, v > 0 else { return }
        var c = Custo(id: UUID(), em: em, tipo: .combustivel, valorCent: Int((v * 100).rounded()))
        c.mililitros = litros.map { Int(($0 * 1000).rounded()) }
        c.precoLitroMilesimo = precoLitro.map { Int(($0 * 1000).rounded()) }
            ?? (informarLitros ? litrosDigitados.flatMap { $0 > 0 ? Int((v / $0 * 1000).rounded()) : nil } : nil)
        c.posto = posto.isEmpty ? nil : posto
        c.observacao = observacao.isEmpty ? nil : observacao
        // Onde abasteceu: só se o GPS do turno tinha um ponto de até 5 min antes/depois (nunca inventado)
        if let p = TurnoStore.shared.pontosAtuais.last, abs(p.em.timeIntervalSince(em)) <= 300 {
            c.local = p.coord
        }
        TurnoStore.shared.registrar(c)
        fechar()
    }
}
