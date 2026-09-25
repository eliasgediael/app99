import Foundation
import Vision
import UIKit

// MARK: - Modelo

struct OfertaCorrida {
    let valor: Double              // R$ que aparece na oferta
    let kmAtePassageiro: Double    // distância de busca
    let kmViagem: Double           // distância até o destino
    let minAtePassageiro: Int?     // opcional, se a 99 mostrar
    let minViagem: Int?
    let textoBruto: String         // útil pra depurar quando o layout da 99 mudar
}

enum ErroOCR: LocalizedError {
    case imagemInvalida
    case valorNaoEncontrado
    case distanciasNaoEncontradas(Int)

    var errorDescription: String? {
        switch self {
        case .imagemInvalida:                 return "Imagem inválida"
        case .valorNaoEncontrado:             return "Valor da corrida não encontrado"
        case .distanciasNaoEncontradas(let n): return "Encontrei \(n) distância(s), esperava 2"
        }
    }
}

// MARK: - OCR

final class LeitorOferta99 {

    /// Área da tela que o Vision vai ler (coordenadas normalizadas, origem no canto INFERIOR esquerdo).
    /// O card da oferta da 99 fica na parte de baixo; ignorar o mapa evita lixo (nomes de rua, horário etc.)
    /// e deixa o OCR mais rápido. Ajuste se o seu layout for diferente.
    var regiaoDeInteresse = CGRect(x: 0, y: 0, width: 1, height: 0.65)

    /// `.accurate` lê melhor, mas usa bem mais memória. A extensão de gravação usa `.fast`
    /// pra ficar longe do limite de 50 MB.
    var nivel: VNRequestTextRecognitionLevel

    init(nivel: VNRequestTextRecognitionLevel = .accurate) {
        self.nivel = nivel
    }

    func ler(imagem: UIImage) async throws -> OfertaCorrida {
        let linhas = try await reconhecerTexto(em: imagem)
        return try ParserOferta99.extrair(de: linhas)
    }

    /// Retorna as linhas de texto na ordem de leitura (cima → baixo, esquerda → direita).
    func reconhecerTexto(em imagem: UIImage) async throws -> [String] {
        guard let cgImage = imagem.cgImage else { throw ErroOCR.imagemInvalida }
        let regiao = regiaoDeInteresse
        let nivel = nivel

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            return try LeitorOferta99.reconhecer(com: handler, regiao: regiao, nivel: nivel)
        }.value
    }

    /// Versão síncrona pra extensão, que já roda numa fila própria.
    /// O frame vai direto pro Vision, sem virar UIImage/CGImage (sem cópia extra na memória).
    func reconhecerTexto(em pixelBuffer: CVPixelBuffer,
                         orientacao: CGImagePropertyOrientation) throws -> [String] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientacao)
        return try LeitorOferta99.reconhecer(com: handler, regiao: regiaoDeInteresse, nivel: nivel)
    }

    private static func reconhecer(com handler: VNImageRequestHandler,
                                   regiao: CGRect,
                                   nivel: VNRequestTextRecognitionLevel) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = nivel
        request.recognitionLanguages = ["pt-BR"]
        request.usesLanguageCorrection = false   // correção atrapalha números
        request.regionOfInterest = regiao

        try handler.perform([request])

        let observacoes = request.results ?? []
        let ordenadas = observacoes.sorted { a, b in
            let dy = a.boundingBox.midY - b.boundingBox.midY
            if abs(dy) > 0.01 { return dy > 0 }            // y maior = mais pra cima
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return ordenadas.compactMap { $0.topCandidates(1).first?.string }
    }
}

// MARK: - Parser (Regex)

enum ParserOferta99 {

    // R$ 12,50 | R$12,50 | R$ 1.234,00 | RS 12,50 (OCR às vezes lê $ como S ou 5)
    private static let regexValor = try! NSRegularExpression(
        pattern: #"R\s?[$S5]\s?(\d{1,3}(?:\.\d{3})*[,.]\d{2})"#
    )

    // 1,2 km | 1.2km | 800 m — o lookahead impede casar "5 min" como metros
    private static let regexDistancia = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s?(km|m)(?![a-zà-ú])"#,
        options: [.caseInsensitive]
    )

    // 3 min | 12min
    private static let regexMinutos = try! NSRegularExpression(
        pattern: #"(\d+)\s?min"#,
        options: [.caseInsensitive]
    )

    static func extrair(de linhas: [String]) throws -> OfertaCorrida {
        let texto = linhas.joined(separator: "\n")

        // Maior valor em R$ = valor da corrida (evita pegar bônus "+R$ 2,00" ou "R$ 1,90/km")
        guard let valor = capturas(regexValor, em: texto).compactMap(converterReais).max() else {
            throw ErroOCR.valorNaoEncontrado
        }

        // Na 99 a 1ª distância é a busca e a 2ª é a viagem
        let distancias = capturasDistancia(em: texto).filter { $0 > 0 && $0 < 200 }
        guard distancias.count >= 2 else {
            throw ErroOCR.distanciasNaoEncontradas(distancias.count)
        }

        let minutos = capturas(regexMinutos, em: texto).compactMap { Int($0) }

        return OfertaCorrida(
            valor: valor,
            kmAtePassageiro: distancias[0],
            kmViagem: distancias[1],
            minAtePassageiro: minutos.first,
            minViagem: minutos.dropFirst().first,
            textoBruto: texto
        )
    }

    // MARK: Helpers

    private static func capturas(_ regex: NSRegularExpression, em texto: String) -> [String] {
        let ns = texto as NSString
        return regex.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func capturasDistancia(em texto: String) -> [Double] {
        let ns = texto as NSString
        return regexDistancia.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .compactMap { m -> Double? in
                let numero = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                let unidade = ns.substring(with: m.range(at: 2)).lowercased()
                guard let v = Double(numero) else { return nil }
                return unidade == "m" ? v / 1000 : v
            }
    }

    /// "1.234,56" / "12,50" / "12.50" → Double
    private static func converterReais(_ s: String) -> Double? {
        let inteiro = String(s.dropLast(3)).replacingOccurrences(of: ".", with: "")
        let centavos = String(s.suffix(2))
        return Double("\(inteiro).\(centavos)")
    }
}
