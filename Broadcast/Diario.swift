import Foundation

/// Totais por dia + linha do tempo, guardados na própria extensão (sobrevivem entre transmissões,
/// atualizações e renovações do AltStore). O app recebe cópias pelo CanalDarwin.
/// Usar sempre na mesma fila (a filaOCR do SampleHandler) — inclusive os envios, pra não
/// misturar pacotes no mesmo canal.
final class Diario {
    private let chaveDias = "diario"
    private let chaveSeq = "linhaSeq"
    private let chaveIdCorrida = "corridaId"
    private let chaveIdOferta = "ofertaId"
    private let limiteEventos = 1500

    private var dias: [Int: DiaRelatorio] = [:]
    private var eventos: [EventoLinha] = []
    private var marcoTempo: Date?

    private lazy var arquivoEventos: URL? = {
        let pasta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let pasta else { return nil }
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("linha-do-tempo.json")
    }()

    init() {
        if let dados = UserDefaults.standard.data(forKey: chaveDias),
           let lista = try? JSONDecoder().decode([DiaRelatorio].self, from: dados) {
            dias = Dictionary(uniqueKeysWithValues: lista.map { ($0.dia, $0) })
        }
        if let url = arquivoEventos, let dados = try? Data(contentsOf: url),
           let lista = try? JSONDecoder().decode([EventoLinha].self, from: dados) {
            eventos = lista
        }
    }

    var hoje: DiaRelatorio { dias[DiaRelatorio.numero()] ?? DiaRelatorio(dia: DiaRelatorio.numero()) }

    /// Últimos dias com algum dado, do mais antigo pro mais novo.
    func ultimos(_ n: Int) -> [DiaRelatorio] {
        Array(dias.values.sorted { $0.dia < $1.dia }.suffix(n))
    }

    // MARK: Totais (só o MotorCorrida chama)

    func contarOferta() {
        alterarHoje { $0.ofertas += 1 }
    }

    /// Só corrida CONFIRMADA.
    func somarConfirmada(valorCent: Int, custoCent: Int, metros: Int) {
        alterarHoje {
            $0.corridas += 1
            $0.faturadoCent += valorCent
            $0.custoCent += custoCent
            $0.metros += metros
        }
    }

    /// Corrida ESTIMADA: fica separada, fora do faturamento principal.
    func somarEstimada(valorCent: Int) {
        alterarHoje {
            $0.estimadas += 1
            $0.estimadoCent += valorCent
        }
    }

    func zerarHoje() {
        alterarHoje { $0 = DiaRelatorio(dia: $0.dia) }
        adicionar(EventoLinha(seq: 0, em: Date(), tipo: .diaZerado, origem: .sistema))
    }

    func novoIdOferta() -> Int {
        let id = UserDefaults.standard.integer(forKey: chaveIdOferta) + 1
        UserDefaults.standard.set(id, forKey: chaveIdOferta)
        return id
    }

    func novoIdCorrida() -> Int {
        let id = UserDefaults.standard.integer(forKey: chaveIdCorrida) + 1
        UserDefaults.standard.set(id, forKey: chaveIdCorrida)
        return id
    }

    // MARK: Linha do tempo

    /// Dá número ao evento, guarda e já manda pro app (se ele não estiver escutando, ele pede depois).
    func adicionar(_ evento: EventoLinha) {
        var e = evento
        e.seq = UserDefaults.standard.integer(forKey: chaveSeq) + 1
        UserDefaults.standard.set(e.seq, forKey: chaveSeq)
        eventos.append(e)
        if eventos.count > limiteEventos { eventos.removeFirst(eventos.count - limiteEventos) }
        salvarEventos()
        EventoLinha.canal.enviar(e.campos)
    }

    /// Eventos com seq maior que `seq`, no máximo `limite`.
    func eventos(depois seq: Int, limite: Int = 100) -> [EventoLinha] {
        Array(eventos.filter { $0.seq > seq }.prefix(limite))
    }

    private func salvarEventos() {
        guard let url = arquivoEventos, let dados = try? JSONEncoder().encode(eventos) else { return }
        try? dados.write(to: url, options: .atomic)
    }

    // MARK: Tempo com a leitura ligada

    func comecarTempo() { marcoTempo = Date() }

    /// Soma o tempo desde o último marco. `forcar` grava mesmo se passou pouco tempo.
    func acumularTempo(forcar: Bool = false) {
        guard let marco = marcoTempo else { return }
        let agora = Date()
        let passou = agora.timeIntervalSince(marco)
        guard forcar || passou >= 60 else { return }
        marcoTempo = agora
        alterarHoje { $0.segundos += Int(passou) }
    }

    func pararTempo() {
        acumularTempo(forcar: true)
        marcoTempo = nil
    }

    // MARK: Persistência dos totais

    private func alterarHoje(_ mudar: (inout DiaRelatorio) -> Void) {
        var dia = hoje
        mudar(&dia)
        dias[dia.dia] = dia
        salvar()
    }

    private func salvar() {
        // Guarda só os últimos 60 dias (o histórico completo fica no app)
        let lista = ultimos(60)
        dias = Dictionary(uniqueKeysWithValues: lista.map { ($0.dia, $0) })
        if let dados = try? JSONEncoder().encode(lista) {
            UserDefaults.standard.set(dados, forKey: chaveDias)
        }
    }
}

/// Reconhece as telas da 99 depois do aceite, pelos textos dos botões.
/// Os textos de fim de corrida não foram vistos na 99 Moto ainda: lista conservadora.
enum TelaCorrida {
    case aCaminho       // "Cheguei no local"
    case embarque       // "Iniciar corrida": no local, esperando o passageiro
    case aBordo         // "Finalizar corrida": passageiro a bordo (NÃO é fim)
    case fim            // tela de corrida encerrada / avaliação
    case cancelada
    case outra

    /// Só vale como botão/título: uma linha curta que começa com o texto (ex.: "Finalizar corrida" ou
    /// "> Finalizar corrida"), não uma frase que cita o texto no meio.
    static func identificar(_ linhas: [String]) -> TelaCorrida {
        let botoes = linhas.map(normalizar)

        func temLinha(_ textos: [String], folga: Int = 12) -> Bool {
            botoes.contains { linha in
                textos.contains { linha.hasPrefix($0) && linha.count <= $0.count + folga }
            }
        }

        let avisosCancelamento = ["cancelou", "corrida cancelada", "viagem cancelada"]
        if botoes.contains(where: { linha in linha.count <= 60 && avisosCancelamento.contains { linha.contains($0) } }) {
            return .cancelada
        }
        if temLinha(["corrida finalizada", "viagem finalizada", "corrida concluida", "viagem concluida",
                     "corrida encerrada", "avalie o passageiro", "avalie seu passageiro",
                     "como foi a corrida", "como foi sua corrida", "como foi a viagem"], folga: 20) {
            return .fim
        }
        if temLinha(["finalizar corrida", "finalizar viagem", "encerrar corrida"]) {
            return .aBordo
        }
        if temLinha(["iniciar corrida", "iniciar viagem"]) {
            return .embarque
        }
        if temLinha(["cheguei"]) {
            return .aCaminho
        }
        return .outra
    }

    /// Minúsculas, sem acento, só letras/números/espaços, sem espaço nas pontas.
    private static func normalizar(_ s: String) -> String {
        let dobrado = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let limpo = String(dobrado.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return limpo.split(separator: " ").joined(separator: " ")
    }
}
