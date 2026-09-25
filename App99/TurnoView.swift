import SwiftUI

/// Topo da tela inicial: sem turno → botão "Iniciar turno"; com turno → painel de bordo.
/// Poucos números, os mais importantes grandes; detalhes no resumo.
struct PainelTurno: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var monitor: MonitorExtensao

    @State private var seletor = SeletorTransmissao()
    @State private var confirmarEncerrar = false
    @State private var resumoAberto: Turno?
    @State private var abastecendo = false

    var body: some View {
        Section {
            if let t = turnos.atual {
                TimelineView(.periodic(from: .now, by: 30)) { contexto in
                    painel(t, resumo: turnos.resumo(t, agora: contexto.date))
                }
            } else {
                semTurno
            }
        }
        .sheet(item: $resumoAberto) { t in
            NavigationStack { ResumoTurnoView(turno: t) }
        }
        .sheet(isPresented: $abastecendo) {
            NavigationStack { AbastecimentoView() }
        }
    }

    // MARK: Sem turno

    private var semTurno: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let u = turnos.ultimoEncerrado {
                let r = turnos.resumo(u)
                Button { resumoAberto = u } label: {
                    HStack {
                        NumeroDestaque(valor: Formato.reais(r.faturamentoConfirmado.valor ?? 0),
                                       rotulo: "último turno · \(Datas.curta(u.inicio)) · \(Duracao.curta(r.duracao.valor ?? 0))")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Button {
                turnos.iniciar()
                seletor.abrir()   // o iOS ainda pede o toque em "Iniciar Transmissão"
            } label: {
                Label("Iniciar turno", systemImage: "play.fill")
            }
            .buttonStyle(BotaoGrande())
            Button { abastecendo = true } label: {
                Label("Abastecimento", systemImage: "fuelpump")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
        .background(SeletorView(picker: seletor.picker).frame(width: 1, height: 1).opacity(0.01))
    }

    // MARK: Turno ativo

    private func painel(_ t: Turno, resumo r: ResumoTurno) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t.pausadoAgora ? "TURNO PAUSADO" : "TURNO ATIVO")
                    .font(.caption.bold())
                    .foregroundStyle(t.pausadoAgora ? Color.orange : Color.green)
                Spacer()
                indicador("Leitura", ligado: monitor.ligada)
                indicador("GPS", ligado: r.temGPS)
            }

            NumeroDestaque(valor: Formato.reais(r.faturamentoConfirmado.valor ?? 0),
                           rotulo: "faturamento confirmado", grande: true)

            HStack(alignment: .top) {
                medida(r.porHora, "R$/hora") { Formato.reais($0) }
                Spacer()
                medida(r.porKm, "R$/km") { Formato.reais($0) }
            }
            HStack(alignment: .top) {
                NumeroDestaque(valor: Duracao.curta(r.duracao.valor ?? 0), rotulo: "de turno")
                Spacer()
                medida(r.km, "km") { Formato.km($0) }
            }

            HStack {
                Etiqueta(texto: (r.segmentos.last?.estado ?? .semLeitura).nome.uppercased(),
                         cor: corEstado(r.segmentos.last?.estado ?? .semLeitura))
                Spacer()
                Text("\(r.corridasConfirmadas) corridas · \(Duracao.curta(r.tempoPorEstado[.aguardando] ?? 0)) aguardando")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if r.corridasEstimadas > 0 {
                Text("+ \(r.corridasEstimadas) estimada\(r.corridasEstimadas == 1 ? "" : "s") (≈ \(Formato.reais(r.faturamentoEstimado.valor ?? 0))) fora do total")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button(t.pausadoAgora ? "Retomar" : "Pausar") {
                    t.pausadoAgora ? turnos.retomar() : turnos.pausar()
                }
                .buttonStyle(BotaoGrande(cor: .gray))
                Button("Encerrar") { confirmarEncerrar = true }
                    .buttonStyle(BotaoGrande(cor: .red))
            }
            .confirmationDialog("Encerrar o turno?", isPresented: $confirmarEncerrar, titleVisibility: .visible) {
                Button("Encerrar turno", role: .destructive) {
                    SinalApp.encerrarLeitura.enviar()
                    resumoAberto = turnos.encerrar()
                }
            }

            HStack {
                Button { abastecendo = true } label: { Label("Abastecimento", systemImage: "fuelpump") }
                Spacer()
                if !monitor.ligada {
                    Button { seletor.abrir() } label: { Label("Ligar leitura", systemImage: "record.circle") }
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
        .background(SeletorView(picker: seletor.picker).frame(width: 1, height: 1).opacity(0.01))
    }

    private func medida(_ m: Medida, _ rotulo: String, _ f: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MedidaTexto(medida: m, formatar: f).font(.title3.bold())
            Text(rotulo).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func indicador(_ nome: String, ligado: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ligado ? Color.green : Color.gray).frame(width: 7, height: 7)
            Text(nome).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func corEstado(_ e: EstadoMotorista) -> Color {
        switch e {
        case .emCorrida:  return .green
        case .aCaminho:   return .blue
        case .aguardando: return .secondary
        case .pausado:    return .orange
        case .semLeitura: return .gray
        }
    }
}

// MARK: - Resumo do turno

/// Primeiro os números principais; o resto aparece ao abrir cada parte.
struct ResumoTurnoView: View {
    let turno: Turno
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @Environment(\.dismiss) private var fechar

    var body: some View {
        let r = turnos.resumo(turno)
        List {
            Section {
                NumeroDestaque(valor: Formato.reais(r.faturamentoConfirmado.valor ?? 0),
                               rotulo: "faturamento confirmado", grande: true)
                campo("Resultado após custos", r.resultado) { Formato.reais($0) }
                campo("R$/hora", r.porHora) { Formato.reais($0) }
                campo("R$/km", r.porKm) { Formato.reais($0) }
                campo("Distância", r.km) { Formato.km($0) }
                LabeledContent("Duração", value: Duracao.curta(r.duracao.valor ?? 0))
            } header: {
                Text("\(Datas.curta(turno.inicio)) · \(Self.hora(turno.inicio))–\(turno.fim.map(Self.hora) ?? "agora")")
            }

            Section("Financeiro") {
                campo("Confirmado", r.faturamentoConfirmado) { Formato.reais($0) }
                campo("Estimado (fora do total)", r.faturamentoEstimado) { Formato.reais($0) }
                campo("Abastecimentos", r.combustivel) { Formato.reais($0) }
                campo("Outros custos", r.outrosCustos) { Formato.reais($0) }
                campo("Resultado estimado (custo/km)", r.resultadoEstimado) { Formato.reais($0) }
                campo("Média por corrida", r.mediaPorCorrida) { Formato.reais($0) }
                campo("R$/hora ativo", r.porHoraAtivo) { Formato.reais($0) }
            }

            Section("Tempo") {
                ForEach(EstadoMotorista.allCases, id: \.self) { e in
                    if let s = r.tempoPorEstado[e], s >= 60 {
                        LabeledContent(e.nome) {
                            Text(Duracao.curta(s) + (r.percentual(e).map { String(format: " · %.0f%%", $0 * 100) } ?? ""))
                        }
                    }
                }
            }

            Section("Corridas e ofertas") {
                LabeledContent("Confirmadas", value: "\(r.corridasConfirmadas)")
                if r.corridasEstimadas > 0 { LabeledContent("Estimadas", value: "\(r.corridasEstimadas)") }
                if r.corridasIndeterminadas > 0 { LabeledContent("Indeterminadas", value: "\(r.corridasIndeterminadas)") }
                LabeledContent("Ofertas", value: "\(r.ofertas.count)")
                LabeledContent("Ofertas aceitas", value: "\(r.ofertas.filter { $0.resultado == .aceita }.count)")
            }

            if !r.custos.isEmpty {
                Section("Abastecimentos e custos") {
                    ForEach(r.custos) { c in Text(c.resumo) }
                }
            }

            Section {
                NavigationLink("Linha do tempo") { LinhaDoTempoView(store: linha) }
            } footer: {
                Text("Só corridas CONFIRMADAS entram no faturamento. Toque num número pra ver de onde ele vem. Distância e R$/km dependem do GPS (próxima etapa).")
            }
        }
        .navigationTitle("Resumo do turno")
        .toolbar { Button("OK") { fechar() } }
    }

    private func campo(_ titulo: String, _ m: Medida, _ f: @escaping (Double) -> String) -> some View {
        LabeledContent(titulo) { MedidaTexto(medida: m, formatar: f) }
    }

    private static func hora(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Abastecimento

/// Registro rápido: valor + preço/L → litros calculados (ou litros direto).
struct AbastecimentoView: View {
    @Environment(\.dismiss) private var fechar

    @State private var valor: Double?
    @State private var precoLitro: Double?
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
        TurnoStore.shared.registrar(c)
        fechar()
    }
}
