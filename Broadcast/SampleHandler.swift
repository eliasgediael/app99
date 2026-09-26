import ReplayKit
import Vision
import QuartzCore

/// Recebe os frames da gravação de tela, lê a oferta da 99 e avisa por voz + notificação.
///
/// Limite de memória da extensão: ~50 MB. Por isso:
/// - só 1 frame a cada 0,5 s, e nenhum enquanto um OCR estiver rodando (no máximo 1 frame retido);
/// - o CVPixelBuffer vai direto pro Vision, sem conversão pra imagem;
/// - OCR `.fast` e só nos 65% de baixo da tela.
class SampleHandler: RPBroadcastSampleHandler {

    private let intervaloMinimo: CFTimeInterval = 0.5
    private let janelaRepeticao: TimeInterval = 20

    private let filaOCR = DispatchQueue(label: "com.elias.app99.broadcast.ocr", qos: .userInitiated)
    private let trava = NSLock()

    // Protegidos pela `trava`
    private var ocrRodando = false
    private var ultimoFrame: CFTimeInterval = 0

    // Só acessados na `filaOCR`
    private let leitor = LeitorOferta99(nivel: .fast)
    private var calculadora = CalculadoraCorrida(config: ConfigMoto())   // trocada pelos ajustes do app ao iniciar
    private var avisadasEm: [String: Date] = [:]
    private let diario = Diario()
    /// Único lugar que decide estado de corrida e faturamento (ver MotorCorrida).
    private lazy var motor = MotorCorrida(diario: diario)

    private var appNaFrenteAte = Date.distantPast   // Apex aberto na tela: não ler
    private var modoTeste = false                     // print de teste: avisa, mas não conta

    // Só na thread principal
    private var observadorPedido: ObservadorDarwin?
    private var observadoresApp: [ObservadorDarwin] = []
    private var receptorPedidoLinha: ReceptorDarwin?

    // MARK: Ciclo da transmissão

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Ajustes do app (valores da moto, voz) chegam por Darwin notifications;
        // podem chegar de novo a qualquer hora se você mudar algo no app.
        let receptor = ReceptorAjustes.shared
        receptor.aoReceber = { [weak self] in self?.ajustesChegaram() }
        receptor.escutar()

        // O app pede o relatório quando abre; respondemos com os últimos dias
        observadorPedido = ObservadorDarwin(DiaRelatorio.nomePedido) { [weak self] in self?.enviarRelatorio() }
        // O app pede a linha do tempo a partir do último evento que tem
        receptorPedidoLinha = ReceptorDarwin(canal: EventoLinha.canalPedido) { [weak self] campos in
            self?.enviarEventos(depois: campos[0])
        }
        filaOCR.async {
            self.diario.comecarTempo()
            self.diario.adicionar(EventoLinha(seq: 0, em: Date(), tipo: .leituraIniciada, origem: .sistema))
        }
        observadoresApp = SinalApp.allCases.map { sinal in
            ObservadorDarwin(sinal.nome) { [weak self] in self?.appAvisou(sinal) }
        }

        SinalExtensao.iniciou.enviar()   // o app responde mandando os ajustes
        pedirAjustes(tentativa: 1)
    }

    private func appAvisou(_ sinal: SinalApp) {
        filaOCR.async {
            switch sinal {
            case .naFrente:    self.appNaFrenteAte = Date().addingTimeInterval(8)   // o app repete a cada 4 s
            case .saiu:        self.appNaFrenteAte = .distantPast
            case .testeInicio: self.modoTeste = true; self.appNaFrenteAte = .distantPast
            case .testeFim:    self.modoTeste = false
            case .zerarHoje:
                self.diario.zerarHoje()
                self.motor.esquecer()
                DiaRelatorio.canal.enviar(self.diario.hoje.campos)
            case .encerrarLeitura:
                // broadcastFinished() roda em seguida e fecha as corridas abertas
                let motivo = NSError(domain: "App99", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: "Turno encerrado no Apex."])
                DispatchQueue.main.async { self.finishBroadcastWithError(motivo) }
            }
        }
    }

    /// Manda os eventos que o app ainda não tem (até 100 por pedido; ele pede de novo se faltar).
    private func enviarEventos(depois seq: Int) {
        filaOCR.async {
            for e in self.diario.eventos(depois: seq) {
                EventoLinha.canal.enviar(e.campos)
            }
        }
    }

    /// Manda os últimos 7 dias pro app (se ele não estiver aberto, ninguém escuta e tudo bem).
    private func enviarRelatorio() {
        filaOCR.async {
            self.diario.acumularTempo(forcar: true)
            for dia in self.diario.ultimos(7) {
                DiaRelatorio.canal.enviar(dia.campos)
            }
        }
    }

    private var ajustesRecebidos = false   // só na thread principal

    /// Pede de novo a cada 2 s; depois de 5 tentativas segue com o padrão.
    private func pedirAjustes(tentativa: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.ajustesRecebidos else { return }
            if tentativa < 5 {
                SinalExtensao.pedirAjustes.enviar()
                self.pedirAjustes(tentativa: tentativa + 1)
            } else {
                Notificador.enviar("Leitura ligada, mas seus ajustes não chegaram: usando o padrão "
                                   + "(mínimo \(Formato.reais(ConfigMoto.atual.minimoPorKm))/km). Abra o Apex pra enviar.")
            }
        }
    }

    private func ajustesChegaram() {
        let config = ConfigMoto.atual
        filaOCR.async {
            self.calculadora = CalculadoraCorrida(config: config)
            self.motor.custoPorKm = config.custoPorKm
        }
        SinalExtensao.ajustesRecebidos.enviar()
        enviarRelatorio()   // o app está aberto e escutando

        guard !ajustesRecebidos else { return }   // avisa só na primeira vez
        ajustesRecebidos = true
        Notificador.enviar("Leitura ligada. Mínimo \(Formato.reais(config.minimoPorKm))/km. Abra a 99.")
        Task { @MainActor in await Narrador.shared.falarSeLigado("Leitor da 99 ligado.") }
    }

    override func broadcastFinished() {
        SinalExtensao.terminou.enviar()
        filaOCR.sync {
            avisadasEm.removeAll()
            motor.encerrarTudo()   // corridas abertas viram ESTIMADA/INDETERMINADA, nunca CONFIRMADA
            diario.adicionar(EventoLinha(seq: 0, em: Date(), tipo: .leituraEncerrada, origem: .sistema))
            diario.pararTempo()
            let hoje = diario.hoje
            if hoje.corridas > 0 || hoje.ofertas > 0 {
                Notificador.enviarResumo(hoje)
            }
            for dia in diario.ultimos(7) {
                DiaRelatorio.canal.enviar(dia.campos)
            }
        }
    }

    // MARK: Frames

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let agora = CACurrentMediaTime()
        trava.lock()
        guard !ocrRodando, agora - ultimoFrame >= intervaloMinimo else {
            trava.unlock()
            return
        }
        ocrRodando = true
        ultimoFrame = agora
        trava.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            liberarOCR()
            return
        }
        let orientacao = orientacao(de: sampleBuffer)

        filaOCR.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                self.analisar(pixelBuffer, orientacao: orientacao)
            }
            self.liberarOCR()
        }
    }

    private func liberarOCR() {
        trava.lock()
        ocrRodando = false
        trava.unlock()
    }

    private func orientacao(de sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        if let valor = CMGetAttachment(sampleBuffer,
                                       key: RPVideoSampleOrientationKey as CFString,
                                       attachmentModeOut: nil) as? NSNumber,
           let orientacao = CGImagePropertyOrientation(rawValue: valor.uint32Value) {
            return orientacao
        }
        return .up
    }

    // MARK: Análise (filaOCR)

    private func analisar(_ pixelBuffer: CVPixelBuffer, orientacao: CGImagePropertyOrientation) {
        diario.acumularTempo()
        guard Date() >= appNaFrenteAte else { return }   // é a tela do próprio Apex

        let linhas: [String]
        do {
            linhas = try leitor.reconhecerTexto(em: pixelBuffer, orientacao: orientacao)
        } catch {
            SinalExtensao.falhaOCR.enviar()
            return
        }
        SinalExtensao.leitura.enviar()
        let agora = Date()

        if let oferta = try? ParserOferta99.extrair(de: linhas), MotorCorrida.plausivel(oferta) {
            SinalExtensao.oferta.enviar()
            // Todo frame vai pro motor (ele precisa ver a oferta 2x pra valer). Print de teste não conta.
            if !modoTeste { motor.observar(.oferta(oferta), em: agora) }

            // Aviso imediato, sem esperar o motor: a oferta dura poucos segundos
            guard ehNova(oferta) else { return }
            SinalExtensao.aviso.enviar()
            let analise = calculadora.analisar(oferta)
            let frase = analise.fraseFalada
            Notificador.enviar(analise)
            Task { @MainActor in await Narrador.shared.falarSeLigado(frase) }
            return
        }

        guard !modoTeste else { return }
        let tela: TelaLida
        switch TelaCorrida.identificar(linhas) {
        case .aCaminho:  tela = .aCaminho
        case .embarque:  tela = .embarque
        case .aBordo:    tela = .aBordo
        case .fim:       tela = .fim(valorCent: ParserOferta99.maiorValorCent(em: linhas))
        case .cancelada: tela = .cancelada
        case .outra:     tela = .outra
        }
        motor.observar(tela, em: agora)
    }

    /// Mesma oferta (valor + distâncias) só é avisada de novo depois de 20 s.
    private func ehNova(_ o: OfertaCorrida) -> Bool {
        let chave = String(format: "%.2f|%.2f|%.2f", o.valor, o.kmAtePassageiro, o.kmViagem)
        let agora = Date()
        avisadasEm = avisadasEm.filter { agora.timeIntervalSince($0.value) < janelaRepeticao }
        guard avisadasEm[chave] == nil else { return false }
        avisadasEm[chave] = agora
        return true
    }
}
