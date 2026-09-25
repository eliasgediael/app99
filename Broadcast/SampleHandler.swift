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
    private let calculadora = CalculadoraCorrida(config: ConfigMoto())   // valores padrão, fixos por enquanto
    private var avisadasEm: [String: Date] = [:]

    // MARK: Ciclo da transmissão

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SinalExtensao.iniciou.enviar()
        // Confirma na hora se a notificação e o áudio funcionam dentro da extensão
        Notificador.enviar("Leitura ligada. Abra a 99.")
        Task { @MainActor in await Narrador.shared.falar("Leitor da 99 ligado.") }
    }

    override func broadcastFinished() {
        SinalExtensao.terminou.enviar()
        filaOCR.sync { avisadasEm.removeAll() }
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
        let linhas: [String]
        do {
            linhas = try leitor.reconhecerTexto(em: pixelBuffer, orientacao: orientacao)
        } catch {
            SinalExtensao.falhaOCR.enviar()
            return
        }
        SinalExtensao.leitura.enviar()

        // A maioria dos frames não tem oferta — silêncio
        guard let oferta = try? ParserOferta99.extrair(de: linhas) else { return }
        SinalExtensao.oferta.enviar()

        guard ehNova(oferta) else { return }
        SinalExtensao.aviso.enviar()

        let analise = calculadora.analisar(oferta)
        let frase = analise.fraseFalada
        Notificador.enviar(analise)
        Task { @MainActor in await Narrador.shared.falar(frase) }
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
