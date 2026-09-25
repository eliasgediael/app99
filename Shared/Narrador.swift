import AVFoundation

/// Fala o resultado em pt-BR por cima do app da 99 (abaixa o volume de outros áudios em vez de parar).
/// `falar` só retorna quando a fala termina — importante no App Intent, senão o iOS
/// suspende o processo no meio da frase.
@MainActor
final class Narrador: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = Narrador()

    private let sintetizador = AVSpeechSynthesizer()
    private var continuacao: CheckedContinuation<Void, Never>?
    private var falaAtual: ObjectIdentifier?

    nonisolated static let chaveVelocidade = "velocidadeFala"
    nonisolated static let velocidadePadrao = 0.50   // 0.5 = normal do iPhone

    nonisolated static let chaveFalar = "falarResultado"

    /// Ajustável na tela de Ajustes do app (chega na extensão via AjustesCompartilhados).
    var velocidade: Float {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.chaveVelocidade) != nil else { return Float(Self.velocidadePadrao) }
        return Float(d.double(forKey: Self.chaveVelocidade))
    }

    /// Desligada por padrão: com música tocando, voz + 99 + música vira bagunça; a notificação basta.
    nonisolated static var vozLigada: Bool {
        UserDefaults.standard.bool(forKey: chaveFalar)
    }

    /// Fala só se "Falar resultado" estiver ligado nos Ajustes.
    func falarSeLigado(_ texto: String) async {
        guard Self.vozLigada else { return }
        await falar(texto)
    }

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    func falar(_ texto: String) async {
        // Se já estava falando (print novo em cima de outro), corta e libera quem esperava
        encerrarFalaPendente()
        sintetizador.stopSpeaking(at: .immediate)

        configurarSessaoDeAudio()

        let fala = AVSpeechUtterance(string: texto)
        fala.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        fala.rate = velocidade
        fala.preUtteranceDelay = 0
        fala.postUtteranceDelay = 0

        await withCheckedContinuation { cont in
            continuacao = cont
            falaAtual = ObjectIdentifier(fala)
            sintetizador.speak(fala)
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Sessão de áudio

    private func configurarSessaoDeAudio() {
        let sessao = AVAudioSession.sharedInstance()
        do {
            try sessao.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try sessao.setActive(true)
        } catch {
            print("Erro na sessão de áudio: \(error)")
        }
    }

    // MARK: Delegate

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.terminou(id) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.terminou(id) }
    }

    private func terminou(_ id: ObjectIdentifier) {
        guard id == falaAtual else { return }   // ignora callback de fala antiga cancelada
        encerrarFalaPendente()
    }

    private func encerrarFalaPendente() {
        continuacao?.resume()
        continuacao = nil
        falaAtual = nil
    }
}
