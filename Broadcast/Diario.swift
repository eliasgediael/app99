import Foundation

/// Totais por dia guardados na própria extensão (o UserDefaults dela sobrevive entre transmissões,
/// atualizações e renovações do AltStore). O app recebe uma cópia pelo CanalDarwin.
/// Usar sempre na mesma fila (a filaOCR do SampleHandler).
final class Diario {
    private let chave = "diario"
    private var dias: [Int: DiaRelatorio] = [:]
    private var marcoTempo: Date?

    init() {
        if let dados = UserDefaults.standard.data(forKey: chave),
           let lista = try? JSONDecoder().decode([DiaRelatorio].self, from: dados) {
            dias = Dictionary(uniqueKeysWithValues: lista.map { ($0.dia, $0) })
        }
    }

    var hoje: DiaRelatorio { dias[DiaRelatorio.numero()] ?? DiaRelatorio(dia: DiaRelatorio.numero()) }

    /// Últimos dias com algum dado, do mais antigo pro mais novo.
    func ultimos(_ n: Int) -> [DiaRelatorio] {
        Array(dias.values.sorted { $0.dia < $1.dia }.suffix(n))
    }

    // MARK: Registro

    func contarOferta() {
        alterarHoje { $0.ofertas += 1 }
    }

    func registrarCorrida(_ a: AnaliseCorrida) {
        alterarHoje {
            $0.corridas += 1
            $0.faturadoCent += Int((a.oferta.valor * 100).rounded())
            $0.custoCent += Int((a.custoEstimado * 100).rounded())
            $0.metros += Int((a.kmTotal * 1000).rounded())
        }
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

    // MARK: Persistência

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
            UserDefaults.standard.set(dados, forKey: chave)
        }
    }
}

/// Reconhece as telas da 99 depois do aceite, pelos textos dos botões.
enum TelaCorrida {
    case aCaminho       // "Cheguei no local" / "Iniciar corrida": aceitou, ainda sem passageiro
    case emViagem       // "Finalizar corrida": passageiro a bordo — conta como feita
    case cancelada      // aviso de cancelamento
    case outra

    static func identificar(_ linhas: [String]) -> TelaCorrida {
        let texto = linhas.joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))

        if texto.contains("cancelou") || texto.contains("corrida cancelada") || texto.contains("viagem cancelada") {
            return .cancelada
        }
        if texto.contains("finalizar corrida") || texto.contains("finalizar viagem") || texto.contains("encerrar corrida") {
            return .emViagem
        }
        if texto.contains("cheguei") || texto.contains("iniciar corrida") || texto.contains("iniciar viagem") {
            return .aCaminho
        }
        return .outra
    }
}
