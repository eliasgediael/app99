import Foundation

/// Turnos e custos, salvos no app. Cada ação vira evento na linha do tempo (origem: você).
/// O resto do turno (ofertas, corridas, estados) vem da leitura e é calculado em AnaliseTurno.
@MainActor
final class TurnoStore: ObservableObject {
    static let shared = TurnoStore()

    @Published private(set) var turnos: [Turno] = []
    @Published private(set) var custos: [Custo] = []

    /// Pontos de GPS do turno atual (os antigos ficam em gps-<id>.json).
    private(set) var pontosAtuais: [PontoGPS] = []
    private var pontosSalvosEm = Date.distantPast
    private let retencaoGPS: TimeInterval = 90 * 86_400

    private let pasta: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

    var atual: Turno? { turnos.last(where: \.ativo) }
    var ultimoEncerrado: Turno? { turnos.last(where: { !$0.ativo }) }

    init() {
        turnos = carregar("turnos.json") ?? []
        custos = carregar("custos.json") ?? []
        if let t = atual { pontosAtuais = pontos(de: t) }
        apagarGPSAntigo()
    }

    // MARK: Turno

    @discardableResult
    func iniciar(em agora: Date = Date()) -> Turno {
        if let t = atual { return t }
        let t = Turno(id: UUID(), inicio: agora)
        turnos.append(t)
        salvarTurnos()
        pontosAtuais = []
        registrar(.turnoIniciado, em: agora, texto: "Turno iniciado", ref: t.id.uuidString)
        Localizacao.shared.ligar()
        return t
    }

    func pausar(em agora: Date = Date()) {
        guard let i = indiceAtual, !turnos[i].pausadoAgora else { return }
        turnos[i].pausas.append(Intervalo(inicio: agora))
        salvarTurnos()
        registrar(.turnoPausado, em: agora, texto: "Pausa")
    }

    func retomar(em agora: Date = Date()) {
        guard let i = indiceAtual, turnos[i].pausadoAgora else { return }
        turnos[i].pausas[turnos[i].pausas.count - 1].fim = agora
        salvarTurnos()
        registrar(.turnoRetomado, em: agora, texto: "Fim da pausa")
    }

    @discardableResult
    func encerrar(em agora: Date = Date()) -> Turno? {
        guard let i = indiceAtual else { return nil }
        salvarPontos()   // antes de marcar o fim (depois disso o turno não é mais o atual)
        if turnos[i].pausadoAgora { turnos[i].pausas[turnos[i].pausas.count - 1].fim = agora }
        turnos[i].fim = agora
        salvarTurnos()
        registrar(.turnoEncerrado, em: agora, texto: "Turno encerrado", ref: turnos[i].id.uuidString)
        Localizacao.shared.desligar()   // salva os pontos
        pontosAtuais = []
        return turnos[i]
    }

    private var indiceAtual: Int? { turnos.lastIndex(where: \.ativo) }

    // MARK: Custos

    func registrar(_ custo: Custo) {
        var c = custo
        if c.turno == nil, let t = atual, t.contem(c.em) { c.turno = t.id }
        custos.append(c)
        custos.sort { $0.em < $1.em }
        salvar(custos, "custos.json")

        var e = EventoLinha(seq: 0, em: c.em, tipo: .custoRegistrado, origem: .usuario)
        e.valorCent = c.valorCent
        e.confianca = .confirmado
        e.motivo = .registradoPeloUsuario
        e.texto = c.resumo
        e.ref = c.id.uuidString
        if let l = c.local { e.lat = l.lat; e.lon = l.lon }
        LinhaDoTempoStore.shared.adicionarLocal(e)
    }

    // MARK: Análise

    func resumo(_ turno: Turno, agora: Date = Date()) -> ResumoTurno {
        AnaliseTurno.calcular(turno, eventos: LinhaDoTempoStore.shared.eventos, custos: custos,
                              pontos: turno.id == atual?.id ? pontosAtuais : pontos(de: turno),
                              custoPorKm: ConfigMoto.atual.custoPorKm, agora: agora)
    }

    // MARK: GPS

    /// Guarda 1 ponto a cada 10 m andados ou 15 s parado (o bastante pra ver buracos de sinal).
    func adicionarPonto(_ p: PontoGPS) {
        guard let t = atual, t.contem(p.em) else { return }
        if let u = pontosAtuais.last {
            guard p.em > u.em else { return }
            if p.em.timeIntervalSince(u.em) < 15 && u.coord.distancia(ate: p.coord) < 10 { return }
        }
        pontosAtuais.append(p)
        if Date().timeIntervalSince(pontosSalvosEm) > 60 { salvarPontos() }
    }

    func salvarPontos() {
        guard let t = atual else { return }
        salvar(pontosAtuais, "gps-\(t.id.uuidString).json")
        pontosSalvosEm = Date()
    }

    func registrarGPS(_ tipo: TipoEvento, texto: String) {
        guard atual != nil else { return }
        var e = EventoLinha(seq: 0, em: Date(), tipo: tipo, origem: .gps)
        e.texto = texto
        LinhaDoTempoStore.shared.adicionarLocal(e)
    }

    /// Privacidade: trajetos com mais de 90 dias são apagados (os totais do turno continuam).
    private func apagarGPSAntigo() {
        let limite = Date().addingTimeInterval(-retencaoGPS)
        for t in turnos where (t.fim ?? Date()) < limite {
            if let url = pasta?.appendingPathComponent("gps-\(t.id.uuidString).json") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Chamado a cada evento que chega da leitura: marca onde você estava e o km do turno naquele momento.
    func enriquecer(_ e: inout EventoLinha) {
        guard let t = atual, t.contem(e.data) else { return }
        if let p = pontosAtuais.last(where: { $0.em <= e.data }), e.data.timeIntervalSince(p.em) <= 60 {
            e.lat = p.coord.lat
            e.lon = p.coord.lon
            e.precisaoM = p.precisaoM
        }
        if !pontosAtuais.isEmpty {
            e.kmTurno = Trajeto.calcular(pontosAtuais.filter { $0.em <= e.data }).metros / 1000
        }
    }

    func pontos(de turno: Turno) -> [PontoGPS] {
        carregar("gps-\(turno.id.uuidString).json") ?? []
    }

    // MARK: Persistência

    private func registrar(_ tipo: TipoEvento, em: Date, texto: String, ref: String? = nil) {
        var e = EventoLinha(seq: 0, em: em, tipo: tipo, origem: .usuario)
        e.texto = texto
        e.ref = ref
        e.motivo = .registradoPeloUsuario
        LinhaDoTempoStore.shared.adicionarLocal(e)
    }

    private func salvarTurnos() { salvar(turnos, "turnos.json") }

    private func salvar<T: Encodable>(_ valor: T, _ nome: String) {
        guard let url = pasta?.appendingPathComponent(nome), let dados = try? JSONEncoder().encode(valor) else { return }
        try? dados.write(to: url, options: .atomic)
    }

    private func carregar<T: Decodable>(_ nome: String) -> T? {
        guard let url = pasta?.appendingPathComponent(nome), let dados = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: dados)
    }
}
