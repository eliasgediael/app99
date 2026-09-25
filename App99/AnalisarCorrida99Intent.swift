import AppIntents
import UIKit
import UniformTypeIdentifiers

/// Aparece no app Atalhos como "Analisar corrida 99". Roda em segundo plano, sem abrir o app.
struct AnalisarCorrida99Intent: AppIntent {
    static let title: LocalizedStringResource = "Analisar corrida 99"
    static let description = IntentDescription("Lê o print da oferta da 99 e fala se a corrida compensa.")
    static let openAppWhenRun = false

    @Parameter(title: "Captura de tela", supportedContentTypes: [.image])
    var captura: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let frase: String

        do {
            guard let imagem = UIImage(data: captura.data) else { throw ErroOCR.imagemInvalida }
            let oferta = try await LeitorOferta99().ler(imagem: imagem)
            let analise = CalculadoraCorrida().analisar(oferta)
            frase = analise.fraseFalada
        } catch {
            // Fala o erro em vez de mostrar tela de erro — você está pilotando
            frase = "Não consegui ler a corrida."
        }

        await Narrador.shared.falar(frase)
        return .result(value: frase)   // também sai pro Atalho, se quiser usar "Falar texto"
    }
}
