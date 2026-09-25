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
    let notaPassageiro: Double?    // "4,95 • +999 corridas"; nil se não achar (ex.: passageiro novo)
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

    // "7 min (2,1 km)" — formato do card da 99: minutos + distância entre parênteses.
    // Aceita erros comuns do OCR: "mn"/"m1n", "(" lido como "[", "{" ou "C".
    private static let regexTrecho = try! NSRegularExpression(
        pattern: #"(\d{1,3})\s?m[il1]?n\.?\s*[(\[{C]?\s*(\d{1,3}(?:[.,]\d{1,2})?)\s?(km|m)(?![a-zà-ú])"#,
        options: [.caseInsensitive]
    )

    // Nota do passageiro: 1,00–5,00 com 2 casas, sem R$ antes nem "x" depois (multiplicador "1,3x")
    private static let regexNota = try! NSRegularExpression(
        pattern: #"(?<![\d,.$])([1-5][,.]\d{2})(?![\d,.]|\s?x)"#
    )
    private static let regexReais = try! NSRegularExpression(pattern: #"R\s?[$S5]"#)

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

        // Na 99 o 1º trecho é a busca e o 2º é a viagem.
        // Primeiro tenta o formato "7 min (2,1 km)", que ignora "km" soltos (mapa, avisos).
        let nota = extrairNota(de: linhas)
        let trechos = capturasTrecho(em: texto).filter { $0.km > 0 && $0.km < 200 }
        if trechos.count >= 2 {
            return OfertaCorrida(
                valor: valor,
                kmAtePassageiro: trechos[0].km,
                kmViagem: trechos[1].km,
                minAtePassageiro: trechos[0].min,
                minViagem: trechos[1].min,
                notaPassageiro: nota,
                textoBruto: texto
            )
        }

        // Plano B: quaisquer duas distâncias, na ordem de leitura
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
            notaPassageiro: nota,
            textoBruto: texto
        )
    }

    /// Maior valor em R$ da tela, em centavos (ex.: valor final na tela de fim de corrida).
    static func maiorValorCent(em linhas: [String]) -> Int? {
        capturas(regexValor, em: linhas.joined(separator: "\n")).compactMap(converterReais).max()
            .map { Int(($0 * 100).rounded()) }
    }

    /// 1º: linha com "corridas" (ex.: "4,95 • +999 corridas"), sem R$ (evita "R$ 1,14 ... por corrida").
    /// 2º: linha que é só a nota, quando o OCR separa "4,95" de "+999 corridas".
    static func extrairNota(de linhas: [String]) -> Double? {
        func notaEm(_ s: String) -> Double? {
            let ns = s as NSString
            guard let m = regexNota.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                  let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")),
                  v <= 5 else { return nil }
            return v
        }
        func temReais(_ s: String) -> Bool {
            regexReais.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        }

        for linha in linhas where linha.lowercased().contains("corridas") && !temReais(linha) {
            if let v = notaEm(linha) { return v }
        }
        let enfeites = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "•·*★☆⭐"))
        for linha in linhas {
            let limpa = linha.trimmingCharacters(in: enfeites)
            if limpa.count == 4, let v = notaEm(limpa) { return v }
        }
        return nil
    }

    // MARK: Helpers

    private static func capturas(_ regex: NSRegularExpression, em texto: String) -> [String] {
        let ns = texto as NSString
        return regex.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func capturasTrecho(em texto: String) -> [(min: Int?, km: Double)] {
        let ns = texto as NSString
        return regexTrecho.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                let numero = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: ".")
                let unidade = ns.substring(with: m.range(at: 3)).lowercased()
                guard let v = Double(numero) else { return nil }
                return (Int(ns.substring(with: m.range(at: 1))), unidade == "m" ? v / 1000 : v)
            }
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
