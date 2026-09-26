import Foundation

// MARK: - Turno

/// Uma sessão de trabalho. O que aconteceu nela está na linha do tempo, entre `inicio` e `fim`;
/// aqui ficam só os dados que não vêm da tela (quando começou, pausas).
struct Turno: Codable, Identifiable, Equatable {
    let id: UUID
    let inicio: Date
    var fim: Date?
    var pausas: [Intervalo] = []

    var ativo: Bool { fim == nil }
    var pausadoAgora: Bool { pausas.last.map { $0.fim == nil } ?? false }

    func contem(_ data: Date) -> Bool {
        data >= inicio && data <= (fim ?? .distantFuture)
    }

    func duracao(ate agora: Date = Date()) -> TimeInterval {
        (fim ?? agora).timeIntervalSince(inicio)
    }
}

struct Intervalo: Codable, Equatable {
    var inicio: Date
    var fim: Date?

    func duracao(ate agora: Date = Date()) -> TimeInterval {
        (fim ?? agora).timeIntervalSince(inicio)
    }
}

// MARK: - Custos (abastecimento e outros)

enum TipoCusto: String, Codable, CaseIterable {
    case combustivel, estacionamento, pedagio, lavagem, manutencao, outro

    var nome: String {
        switch self {
        case .combustivel:    return "Abastecimento"
        case .estacionamento: return "Estacionamento"
        case .pedagio:        return "Pedágio"
        case .lavagem:        return "Lavagem"
        case .manutencao:     return "Manutenção"
        case .outro:          return "Outro"
        }
    }
}

/// Registrado à mão (origem: você → CONFIRMADO). Pode estar fora de um turno.
struct Custo: Codable, Identifiable, Equatable {
    let id: UUID
    var em: Date
    var tipo: TipoCusto
    var valorCent: Int
    /// Só combustível: litros × 1000 e preço por litro em milésimos de real (6,290 → 6290).
    var mililitros: Int?
    var precoLitroMilesimo: Int?
    var turno: UUID?
    var posto: String?
    var observacao: String?
    var local: Coordenada?

    var valor: Double { Double(valorCent) / 100 }
    var litros: Double? { mililitros.map { Double($0) / 1000 } }
    var precoLitro: Double? { precoLitroMilesimo.map { Double($0) / 1000 } }

    /// Texto curto pra linha do tempo: "Abastecimento · R$ 20,00 · 3,18 L"
    var resumo: String {
        var partes = [tipo.nome, Formato.reais(valor)]
        if let l = litros { partes.append(String(format: "%.2f L", l).replacingOccurrences(of: ".", with: ",")) }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Localização

struct Coordenada: Codable, Equatable {
    var lat: Double
    var lon: Double

    /// Célula de ~1,2 × 0,6 km (geohash de 6 letras). Regiões saem só do seu histórico:
    /// as células onde você realmente passou, sem nome de bairro inventado.
    var regiao: String { Geohash.codificar(lat: lat, lon: lon, precisao: 6) }

    /// Distância em metros (haversine).
    func distancia(ate b: Coordenada) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - lat) * .pi / 180
        let dLon = (b.lon - lon) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Um ponto do GPS (a coleta entra na Fase 3; o modelo e os filtros já ficam prontos).
struct PontoGPS: Codable, Equatable {
    var em: Date
    var coord: Coordenada
    var precisaoM: Double
    var velocidadeMS: Double?     // do próprio GPS, se ele informar (≥ 0)
}

enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func codificar(lat: Double, lon: Double, precisao: Int) -> String {
        var faixaLat = (-90.0, 90.0), faixaLon = (-180.0, 180.0)
        var resultado = "", bit = 0, ch = 0, par = true
        while resultado.count < precisao {
            if par {
                let meio = (faixaLon.0 + faixaLon.1) / 2
                if lon >= meio { ch |= 1 << (4 - bit); faixaLon.0 = meio } else { faixaLon.1 = meio }
            } else {
                let meio = (faixaLat.0 + faixaLat.1) / 2
                if lat >= meio { ch |= 1 << (4 - bit); faixaLat.0 = meio } else { faixaLat.1 = meio }
            }
            par.toggle()
            if bit < 4 { bit += 1 } else { resultado.append(base32[ch]); bit = 0; ch = 0 }
        }
        return resultado
    }

    /// Centro aproximado da célula (usado só pra dar nome à região, se você ativar).
    static func centro(_ hash: String) -> Coordenada? {
        var faixaLat = (-90.0, 90.0), faixaLon = (-180.0, 180.0)
        var par = true
        for ch in hash {
            guard let i = base32.firstIndex(of: ch) else { return nil }
            for b in stride(from: 4, through: 0, by: -1) {
                let bit = (i >> b) & 1
                if par {
                    let meio = (faixaLon.0 + faixaLon.1) / 2
                    if bit == 1 { faixaLon.0 = meio } else { faixaLon.1 = meio }
                } else {
                    let meio = (faixaLat.0 + faixaLat.1) / 2
                    if bit == 1 { faixaLat.0 = meio } else { faixaLat.1 = meio }
                }
                par.toggle()
            }
        }
        return Coordenada(lat: (faixaLat.0 + faixaLat.1) / 2, lon: (faixaLon.0 + faixaLon.1) / 2)
    }
}

// MARK: - Medida com confiança

/// De onde veio um número.
enum FonteDado: String, Codable {
    case tela           // lido pela leitura da 99
    case gps
    case usuario        // digitado por você
    case configuracao   // valor dos Ajustes (ex.: custo por km)
    case calculo        // combinação de outras medidas
    case relogio        // horários de início/fim/pausa
}

/// Um número + quanto dá pra confiar nele + de onde veio. `valor == nil` = não dá pra saber.
struct Medida: Equatable {
    var valor: Double?
    var confianca: Confianca
    var fonte: FonteDado
    var nota: String? = nil

    static func indeterminada(_ fonte: FonteDado, _ nota: String) -> Medida {
        Medida(valor: nil, confianca: .indeterminado, fonte: fonte, nota: nota)
    }

    /// Confiança de uma conta = a pior das partes.
    static func pior(_ a: Confianca, _ b: Confianca) -> Confianca {
        Confianca(rawValue: max(a.rawValue, b.rawValue)) ?? .indeterminado
    }

    /// a ÷ b, só se os dois existirem e b > 0.
    static func dividir(_ a: Medida, _ b: Medida, fator: Double = 1, nota: String? = nil) -> Medida {
        guard let x = a.valor, let y = b.valor, y > 0 else {
            return .indeterminada(.calculo, nota ?? "faltam dados pra calcular")
        }
        return Medida(valor: x / y * fator, confianca: pior(a.confianca, b.confianca), fonte: .calculo, nota: nota)
    }

    static func subtrair(_ a: Medida, _ b: Medida, nota: String? = nil) -> Medida {
        guard let x = a.valor, let y = b.valor else { return .indeterminada(.calculo, nota ?? "faltam dados pra calcular") }
        return Medida(valor: x - y, confianca: pior(a.confianca, b.confianca), fonte: .calculo, nota: nota)
    }
}
