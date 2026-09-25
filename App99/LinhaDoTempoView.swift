import SwiftUI

/// Guarda no app a linha do tempo que a extensão gera (pelo CanalDarwin).
/// A extensão numera os eventos; o app pede "tudo depois do último que tenho sem buraco".
@MainActor
final class LinhaDoTempoStore: ObservableObject {
    static let shared = LinhaDoTempoStore()

    @Published private(set) var eventos: [EventoLinha] = []   // em ordem de seq (os do app, negativos, primeiro)

    private let retencao: TimeInterval = 90 * 86_400
    private var seqs: Set<Int> = []
    private var receptor: ReceptorDarwin?
    private var ultimoPedido = -1
    private var repedir: Task<Void, Never>?

    private lazy var arquivo: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("linha-do-tempo.json")

    init() {
        if let url = arquivo, let dados = try? Data(contentsOf: url),
           let lista = try? JSONDecoder().decode([EventoLinha].self, from: dados) {
            eventos = lista
            seqs = Set(lista.map(\.seq))
        }
        receptor = ReceptorDarwin(canal: EventoLinha.canal) { [weak self] campos in
            guard let e = EventoLinha(campos: campos) else { return }
            Task { @MainActor in self?.receber(e) }
        }
    }

    /// Evento criado no app (turno, custo, GPS). Seq negativo: nunca se mistura com os da extensão.
    func adicionarLocal(_ evento: EventoLinha) {
        var e = evento
        let proximo = UserDefaults.standard.integer(forKey: "linhaSeqApp") - 1
        UserDefaults.standard.set(proximo, forKey: "linhaSeqApp")
        e.seq = proximo
        guardar(e)
    }

    /// Maior seq tal que não falta nenhum antes dele (a partir do primeiro que temos).
    private var contiguo: Int {
        guard var n = eventos.first(where: { !$0.doApp })?.seq else { return 0 }
        while seqs.contains(n + 1) { n += 1 }
        return n
    }

    /// Pede à extensão os eventos que faltam (se a leitura estiver ligada, ela responde).
    func pedir() {
        ultimoPedido = contiguo
        EventoLinha.canalPedido.enviar([ultimoPedido])
    }

    private func receber(_ e: EventoLinha) {
        guard !seqs.contains(e.seq) else { return }
        var e = e
        TurnoStore.shared.enriquecer(&e)   // local e km do turno no momento (quando houver GPS)
        guardar(e)

        // A extensão manda até 100 por pedido: se avançou, pede a próxima página
        repedir?.cancel()
        repedir = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.contiguo != self.ultimoPedido else { return }
            self.pedir()
        }
    }

    private func guardar(_ e: EventoLinha) {
        seqs.insert(e.seq)
        eventos.append(e)
        eventos.sort { $0.seq < $1.seq }

        let limite = Int(Date().timeIntervalSince1970 - retencao)
        if eventos.contains(where: { $0.em < limite }) {
            eventos.removeAll { $0.em < limite }
            seqs = Set(eventos.map(\.seq))
        }
        salvar()
    }

    private func salvar() {
        guard let url = arquivo, let dados = try? JSONEncoder().encode(eventos) else { return }
        try? dados.write(to: url, options: .atomic)
    }
}

// MARK: - Tela

struct LinhaDoTempoView: View {
    @ObservedObject var store: LinhaDoTempoStore
    /// Só os eventos desse período (ex.: um turno). nil = todos.
    var intervalo: DateInterval? = nil

    private var eventos: [EventoLinha] {
        guard let i = intervalo else { return store.eventos }
        return store.eventos.filter { i.contains($0.data) }
    }

    private var porDia: [(dia: Int, eventos: [EventoLinha])] {
        Dictionary(grouping: eventos, by: \.dia)
            .map { ($0.key, $0.value.sorted { ($0.em, $0.seq) > ($1.em, $1.seq) }) }   // mais novo primeiro
            .sorted { $0.dia > $1.dia }
    }

    var body: some View {
        List {
            if eventos.isEmpty {
                Text("Nenhum evento ainda. Os eventos chegam enquanto a leitura está ligada e este app aberto.")
                    .foregroundStyle(.secondary)
            }
            ForEach(porDia, id: \.dia) { grupo in
                Section(Datas.curta(grupo.eventos.first?.data ?? Date())) {
                    ForEach(grupo.eventos, id: \.seq) { e in
                        LinhaEventoView(evento: e)
                    }
                }
            }
        }
        .navigationTitle("Linha do tempo")
        .refreshable { store.pedir() }
        .onAppear { store.pedir() }
    }
}

private struct LinhaEventoView: View {
    let evento: EventoLinha

    private static let hora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.hora.string(from: evento.data))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icone.nome).font(.caption).foregroundStyle(icone.cor)
                    Text(titulo).font(.subheadline.bold())
                    if evento.corrida > 0 {
                        Text("#\(evento.corrida)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let dados { Text(dados).font(.caption) }
                HStack(spacing: 6) {
                    etiqueta(evento.origem.nome, cor: evento.origem == .inferencia ? .orange : .gray)
                    if let c = evento.confianca {
                        etiqueta(c.nome, cor: cor(c))
                    }
                }
                if !motivo.isEmpty {
                    Text(motivo).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var titulo: String {
        if evento.tipo == .transicao {
            let de = evento.estadoAnterior?.nome ?? "—"
            let para = evento.estadoNovo?.nome ?? "—"
            return "ESTADO \(de) → \(para)"
        }
        return evento.tipo.nome
    }

    private var icone: (nome: String, cor: Color) {
        switch evento.tipo {
        case .ofertaDetectada, .ofertaSaiuDaTela:                   return ("tag", .blue)
        case .faturamentoConfirmado:                                return ("checkmark.seal.fill", .green)
        case .faturamentoEstimado:                                  return ("questionmark.circle", .orange)
        case .custoRegistrado:                                      return ("fuelpump", .purple)
        case .turnoIniciado, .turnoEncerrado, .turnoPausado, .turnoRetomado: return ("flag", .purple)
        case .gpsSemSinal, .gpsRetomado:                            return ("location", .gray)
        case .leituraIniciada, .leituraEncerrada, .diaZerado:       return ("record.circle", .gray)
        default:                                                    return ("circle.fill", .secondary)
        }
    }

    private var dados: String? {
        if let t = evento.texto { return t }
        var partes: [String] = []
        if evento.valorCent > 0 { partes.append(Formato.reais(Double(evento.valorCent) / 100)) }
        if evento.buscaM > 0 || evento.viagemM > 0 {
            let total = Double(evento.buscaM + evento.viagemM) / 1000
            partes.append("\(Formato.km(total)) (busca \(Formato.km(Double(evento.buscaM) / 1000)))")
        }
        if evento.nota100 > 0 { partes.append("⭐ \(Formato.nota(Double(evento.nota100) / 100))") }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    private var motivo: String {
        var texto = evento.motivo.texto(extra: evento.extra)
        // Encerramentos por outro motivo (tempo, leitura desligada…) também dizem o que faltou
        if evento.motivo != .evidenciaIncompleta, evento.estadoNovo?.encerrada == true, evento.extra != 0 {
            texto += " Faltou: " + Falta.descrever(evento.extra) + "."
        }
        return texto
    }

    private func etiqueta(_ texto: String, cor: Color) -> some View {
        Text(texto)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cor.opacity(0.18), in: Capsule())
            .foregroundStyle(cor)
    }

    private func cor(_ c: Confianca) -> Color {
        switch c {
        case .confirmado:    return .green
        case .estimado:      return .orange
        case .indeterminado: return .gray
        }
    }
}
