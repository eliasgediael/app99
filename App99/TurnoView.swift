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
        let comLeitura = r.temLeitura
        let oferta = r.ofertas.last

        return ScrollView {
            VStack(spacing: Espaco.xl) {
                Pilula(texto: (t.pausadoAgora ? "TURNO PAUSADO" : "TURNO ATIVO") + " • " + Self.duracaoLonga(r.duracao.valor ?? 0),
                       cor: t.pausadoAgora ? Tema.atencao : Tema.positivo,
                       fundo: (t.pausadoAgora ? Tema.atencao : Tema.positivo).opacity(0.14))

                VStack(spacing: 6) {
                    Text(comLeitura ? Formato.reais(r.faturamentoConfirmado.valor ?? 0) : "—")
                        .font(Tipo.heroi)
                        .monospacedDigit()
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(comLeitura ? "(" + Datas.corridas(r.corridasConfirmadas) + ")" : "aguardando a leitura da tela")
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                    if metaDiaria > 0 {
                        BarraMeta(valor: confirmadoHoje, meta: metaDiaria).padding(.top, 8)
                    }
                }

                HStack(spacing: 0) {
                    ritmo("Por hora", comLeitura ? r.porHora.texto({ Formato.reais($0) + "/h" }) : "—")
                    Rectangle().fill(Tema.linha).frame(width: 1, height: 44)
                    ritmo("Por km", comLeitura ? r.porKm.texto({ Formato.reais($0) + "/km" }) : "—")
                }

                HStack(spacing: Espaco.s) {
                    Circle().fill(estado.cor).frame(width: 7, height: 7)
                    Text(estado.nome + " · " + Duracao.curta(agora.timeIntervalSince(desde)))
                    Text("·")
                    Text(r.km.texto(Formato.km))
                    sinal("Leitura", ligado: monitor.ligada)
                    sinal("GPS", ligado: gps.estado == .ativo)
                }
                .font(Tipo.legenda.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)

                alertas

                if let o = oferta {
                    VStack(alignment: .leading, spacing: Espaco.s) {
                        Text("Última oferta").font(Tipo.apoio.weight(.semibold)).foregroundStyle(Tema.textoSecundario)
                        cartaoOferta(o)
                    }
                }

                if let c = r.emAndamento ?? r.feitas.last {
                    Cartao(espaco: 0) {
                        NavigationLink { CorridaDetalheView(c: c, r: r) } label: {
                            HStack(spacing: Espaco.s) {
                                Text(c.feita ? "Última corrida" : (c.aBordoEm == nil ? "Em busca" : "Em corrida"))
                                    .font(Tipo.legenda)
                                    .foregroundStyle(Tema.textoTerciario)
                                LinhaCorrida(c: c)
                            }
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
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

    private func ritmo(_ rotulo: String, _ valor: String) -> some View {
        VStack(spacing: 4) {
            Text(rotulo).font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            Text(valor)
                .font(Tipo.metrica)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    /// Oferta: o que a 99 mostrou. Neutra, sem recomendação e sem somar em nada.
    private func cartaoOferta(_ o: OfertaAnalisada) -> some View {
        let minutos = (o.minBusca ?? 0) + (o.minViagem ?? 0)
        var linha1 = [Formato.reais(Double(o.valorCent) / 100), Formato.km(o.km)]
        if minutos > 0 { linha1.append("\(minutos) min") }
        var linha2: [String] = []
        if minutos > 0 { linha2.append(Formato.reais(Double(o.valorCent) / 100 / (Double(minutos) / 60)) + "/h") }
        if let pk = o.porKm { linha2.append(Formato.reais(pk) + "/km") }
        let situacao: String
        switch o.resultado {
        case .aceita:    situacao = "ACEITA"
        case .naoAceita: situacao = "NÃO ACEITA"
        case .emAberto:  situacao = "NA TELA"
        }
        return Cartao {
            VStack(alignment: .leading, spacing: 8) {
                Pilula(texto: situacao + " • " + Datas.hora(o.em), cor: Tema.textoSecundario, fundo: Tema.superficieAlta)
                Text(linha1.joined(separator: " · "))
                    .font(Tipo.titulo)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                if !linha2.isEmpty {
                    Text(linha2.joined(separator: " · "))
                        .font(Tipo.apoio)
                        .monospacedDigit()
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
        }
    }

    /// "3h 12m"
    static func duracaoLonga(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(m)m" : "\(m / 60)h \(String(format: "%02d", m % 60))m"
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
