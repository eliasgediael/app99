import SwiftUI

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
        Group {
            if let t = turnos.atual {
                TimelineView(.periodic(from: .now, by: 30)) { contexto in
                    ativo(t, r: turnos.resumo(t, agora: contexto.date), agora: contexto.date)
                }
            } else {
                semTurno
            }
        }
        .background(Tema.fundo.ignoresSafeArea())
        .background(SeletorView(picker: seletor.picker).frame(width: 1, height: 1).opacity(0.01))
        .sheet(item: $resumoAberto) { t in
            NavigationStack { ResumoTurnoView(turno: t) }
        }
        .sheet(isPresented: $abastecendo) {
            NavigationStack { AbastecimentoView() }
        }
        .onChange(of: nav.aba) { _ in resumoAberto = nil }
    }

    // MARK: Sem turno

    private var semTurno: some View {
        let registrados = turnos.turnosComRegistro
        let semana = ResumoAgregado(resumos: Historico.turnos(registrados, em: .ultimos7).map { turnos.resumo($0) })
        let trabalhouHoje = !Historico.turnos(registrados, em: .hoje).isEmpty
        let ultimo = registrados.last { !$0.ativo }
        return ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Datas.longaTitulo(Date()))
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                    if trabalhouHoje {
                        Text(Formato.reais(confirmadoHoje))
                            .font(Tipo.heroi)
                            .monospacedDigit()
                            .foregroundStyle(Tema.texto)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("hoje")
                            .font(Tipo.apoio)
                            .foregroundStyle(Tema.textoSecundario)
                    } else {
                        Text("Sem turno hoje")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Tema.texto)
                    }
                    if metaDiaria > 0 && trabalhouHoje {
                        BarraMeta(valor: confirmadoHoje, meta: metaDiaria).padding(.top, 6)
                    }
                }

                if semana.turnos > 0 {
                    Secao("Últimos 7 dias") {
                        GradeMetricas {
                            Metrica(Formato.reais(semana.confirmado), "faturamento")
                            Metrica(semana.porHora, "por hora") { Formato.reais($0) }
                            Metrica("\(semana.corridasConfirmadas)", "corridas")
                        }
                    }
                }

                if let u = ultimo {
                    let r = turnos.resumo(u)
                    Secao("Último turno") {
                        NavigationLink { ResumoTurnoView(turno: u) } label: {
                            HStack(alignment: .center, spacing: Espaco.m) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ResumoTurnoView.titulo(u))
                                        .font(Tipo.apoio.weight(.medium))
                                        .foregroundStyle(Tema.texto)
                                    Text(Duracao.curta(r.duracao.valor ?? 0) + (r.temLeitura ? " · " + Datas.corridas(r.corridasConfirmadas) : ""))
                                        .font(Tipo.legenda)
                                        .foregroundStyle(Tema.textoSecundario)
                                }
                                Spacer()
                                Text(r.temLeitura ? Formato.reais(r.faturamentoConfirmado.valor ?? 0) : "—")
                                    .font(Tipo.valor)
                                    .monospacedDigit()
                                    .foregroundStyle(Tema.texto)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Tema.textoTerciario)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.m)
            .padding(.bottom, Espaco.xl)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Espaco.s) {
                Button {
                    turnos.iniciar()
                    seletor.abrir()   // o iOS ainda pede o toque em "Iniciar Transmissão"
                } label: {
                    Label("Iniciar turno", systemImage: "play.fill")
                }
                .buttonStyle(BotaoPrimario())
                Button("Registrar abastecimento") { abastecendo = true }
                    .font(Tipo.apoio.weight(.semibold))
                    .foregroundStyle(Tema.primaria)
                    .frame(minHeight: 36)
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.m)
            .padding(.bottom, Espaco.s)
            .background(Tema.fundo)
        }
    }

    // MARK: Turno ativo

    private func ativo(_ t: Turno, r: ResumoTurno, agora: Date) -> some View {
        let estado = t.pausadoAgora ? EstadoMotorista.pausado : (r.segmentos.last?.estado ?? .semLeitura)
        let desde = r.segmentos.last?.inicio ?? t.inicio
        let ultimas = Array(r.feitas.suffix(3).reversed())
        let comLeitura = r.temLeitura

        return ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                HStack(spacing: Espaco.s) {
                    PontoEstado(texto: estado.nome, cor: estado.cor)
                    Text(Duracao.curta(agora.timeIntervalSince(desde)))
                        .font(Tipo.apoio.monospacedDigit())
                        .foregroundStyle(Tema.textoSecundario)
                    Spacer()
                    sinal("Leitura", ligado: monitor.ligada)
                    sinal("GPS", ligado: gps.estado == .ativo)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(comLeitura ? Formato.reais(r.faturamentoConfirmado.valor ?? 0) : "—")
                        .font(Tipo.heroi)
                        .monospacedDigit()
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(comLeitura ? "faturamento confirmado" : "aguardando a leitura da tela")
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                    if metaDiaria > 0 {
                        BarraMeta(valor: confirmadoHoje, meta: metaDiaria).padding(.top, 6)
                    }
                }

                GradeMetricas {
                    if comLeitura {
                        Metrica(r.porHora, "por hora") { Formato.reais($0) }
                        Metrica(r.porKm, "por km") { Formato.reais($0) }
                    } else {
                        Metrica("—", "por hora")
                        Metrica("—", "por km")
                    }
                    Metrica(r.km, "km") { Formato.km($0) }
                    Metrica(Duracao.curta(r.duracao.valor ?? 0), "de turno")
                    Metrica(comLeitura ? "\(r.corridasConfirmadas)" : "—",
                            r.corridasEstimadas > 0 ? "corridas · \(r.corridasEstimadas) ≈" : "corridas")
                    Metrica(comLeitura ? Duracao.curta(r.tempoPorEstado[.aguardando] ?? 0) : "—", "sem corrida")
                }

                alertas

                if let c = r.emAndamento {
                    Secao("Agora") {
                        HStack(spacing: Espaco.m) {
                            Image(systemName: c.aBordoEm == nil ? "car.fill" : "person.fill")
                                .foregroundStyle(c.aBordoEm == nil ? Tema.mapaIndoBuscar : Tema.mapaEmCorrida)
                            Text(c.aBordoEm == nil ? "Indo buscar" : "Em corrida")
                                .font(Tipo.apoio.weight(.semibold))
                                .foregroundStyle(Tema.texto)
                            Spacer()
                            if let v = c.valorOfertaCent {
                                Text(Formato.reais(Double(v) / 100))
                                    .font(Tipo.apoio.monospacedDigit())
                                    .foregroundStyle(Tema.textoSecundario)
                            }
                        }
                    }
                }

                if !ultimas.isEmpty {
                    Secao("Últimas corridas", acao: { Button("Ver todas") { nav.aba = .viagens } }) {
                        VStack(spacing: 0) {
                            ForEach(ultimas.indices, id: \.self) { i in
                                NavigationLink { CorridaDetalheView(c: ultimas[i], r: r) } label: {
                                    LinhaCorrida(c: ultimas[i])
                                }
                                .buttonStyle(.plain)
                                if i < ultimas.count - 1 { Divisoria() }
                            }
                        }
                    }
                }

                NavigationLink { ResumoTurnoView(turno: t) } label: {
                    LinhaNavegacao("Resumo do turno", "chart.bar.doc.horizontal")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.m)
            .padding(.bottom, Espaco.xl)
        }
        .safeAreaInset(edge: .bottom) { acoes(t) }
    }

    @ViewBuilder
    private var alertas: some View {
        if gps.estado == .semPermissao {
            Alerta(texto: "Localização desativada", acaoTitulo: "Ativar") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        // Só quando a leitura foi vista ligada e depois parou (reabrir o app zera a contagem)
        if monitor.quantos(.iniciou) > 0 && !monitor.ligada {
            Alerta(texto: "Leitura da tela parada", acaoTitulo: "Ligar") { seletor.abrir() }
        }
    }

    private func acoes(_ t: Turno) -> some View {
        HStack(spacing: Espaco.s) {
            Button(t.pausadoAgora ? "Retomar" : "Pausar") {
                t.pausadoAgora ? turnos.retomar() : turnos.pausar()
            }
            .buttonStyle(BotaoSecundario())
            Button("Abastecer") { abastecendo = true }
                .buttonStyle(BotaoSecundario())
            Button("Encerrar") { confirmarEncerrar = true }
                .buttonStyle(BotaoSecundario(cor: Tema.erro))
        }
        .padding(.horizontal, Espaco.margem)
        .padding(.top, Espaco.m)
        .padding(.bottom, Espaco.s)
        .background(Tema.fundo)
        .confirmationDialog("Encerrar o turno?", isPresented: $confirmarEncerrar, titleVisibility: .visible) {
            Button("Encerrar turno", role: .destructive) {
                SinalApp.encerrarLeitura.enviar()
                resumoAberto = turnos.encerrar()
            }
        }
    }

    /// Faturamento confirmado dos turnos de hoje (inclui o ativo, mesmo que tenha começado ontem).
    private var confirmadoHoje: Double {
        var lista = Historico.turnos(turnos.turnos, em: .hoje)
        if let a = turnos.atual, !lista.contains(where: { $0.id == a.id }) { lista.append(a) }
        return lista.reduce(0) { $0 + (turnos.resumo($1).faturamentoConfirmado.valor ?? 0) }
    }

    private func sinal(_ nome: String, ligado: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ligado ? Tema.positivo : Tema.textoTerciario).frame(width: 6, height: 6)
            Text(nome).font(.caption2.weight(.medium)).foregroundStyle(Tema.textoSecundario)
        }
        .accessibilityLabel("\(nome) \(ligado ? "ligado" : "desligado")")
    }
}

// MARK: - Abastecimento

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
                LabeledContent("Valor pago") {
                    TextField("R$ 0,00", value: $valor, format: formatoReais)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Preço do litro") {
                    TextField("R$ 0,000", value: $precoLitro, format: formatoPreco)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Toggle("Informar litros", isOn: $informarLitros)
                if informarLitros {
                    LabeledContent("Litros") {
                        TextField("0,00", value: $litrosDigitados, format: formatoReais)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } else {
                    LabeledContent("Litros", value: litros.map { String(format: "%.2f L", $0).replacingOccurrences(of: ".", with: ",") } ?? "—")
                }
            }
            Section {
                DatePicker("Quando", selection: $em)
                TextField("Posto", text: $posto)
                TextField("Observação", text: $observacao)
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
        // Local só se o GPS do turno tinha ponto até 5 min do horário informado
        if let p = TurnoStore.shared.pontosAtuais.last, abs(p.em.timeIntervalSince(em)) <= 300 {
            c.local = p.coord
        }
        TurnoStore.shared.registrar(c)
        fechar()
    }
}
