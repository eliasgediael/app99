import Foundation

/// Totais de um dia. A extensão acumula; o app guarda de vez e mostra.
struct DiaRelatorio: Codable, Equatable {
    var dia: Int                 // dias desde 01/01/1970 no fuso local
    var faturadoCent = 0         // soma das corridas CONFIRMADAS (bruto)
    var custoCent = 0            // km × custo por km das confirmadas
    var corridas = 0             // confirmadas
    var metros = 0
    var ofertas = 0              // ofertas diferentes que apareceram
    var segundos = 0             // tempo com a leitura ligada
    var estimadas = 0            // corridas ESTIMADAS (fora do faturamento principal)
    var estimadoCent = 0

    var faturado: Double { Double(faturadoCent) / 100 }
    var estimado: Double { Double(estimadoCent) / 100 }
    var custo: Double { Double(custoCent) / 100 }
    var lucro: Double { faturado - custo }
    var km: Double { Double(metros) / 1000 }
    var horas: Double { Double(segundos) / 3600 }
    var porKm: Double? { km > 0 ? faturado / km : nil }
    var lucroPorHora: Double? { segundos >= 60 ? lucro / horas : nil }

    var data: Date {
        let fuso = TimeInterval(TimeZone.current.secondsFromGMT())
        return Date(timeIntervalSince1970: TimeInterval(dia) * 86_400 - fuso + 43_200)   // meio-dia do dia
    }

    static func numero(de data: Date = Date()) -> Int {
        let fuso = TimeInterval(TimeZone.current.secondsFromGMT(for: data))
        return Int(floor((data.timeIntervalSince1970 + fuso) / 86_400))
    }

    // MARK: Transporte

    static let canal = CanalDarwin(prefixo: "com.elias.app99.rel2", campos: 9)
    /// App → extensão: "me manda os últimos dias"
    static let nomePedido = "com.elias.app99.rel.pedir"

    var campos: [Int] { [dia, faturadoCent, custoCent, corridas, metros, ofertas, segundos, estimadas, estimadoCent] }

    init(dia: Int) { self.dia = dia }

    init?(campos c: [Int]) {
        guard c.count == 9, c[0] > 0 else { return nil }
        dia = c[0]; faturadoCent = c[1]; custoCent = c[2]; corridas = c[3]
        metros = c[4]; ofertas = c[5]; segundos = c[6]; estimadas = c[7]; estimadoCent = c[8]
    }

    // Lê também os dados salvos antes de existir "estimado" (campos que faltam = 0)
    private enum CodingKeys: String, CodingKey {
        case dia, faturadoCent, custoCent, corridas, metros, ofertas, segundos, estimadas, estimadoCent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dia = try c.decode(Int.self, forKey: .dia)
        faturadoCent = try c.decodeIfPresent(Int.self, forKey: .faturadoCent) ?? 0
        custoCent = try c.decodeIfPresent(Int.self, forKey: .custoCent) ?? 0
        corridas = try c.decodeIfPresent(Int.self, forKey: .corridas) ?? 0
        metros = try c.decodeIfPresent(Int.self, forKey: .metros) ?? 0
        ofertas = try c.decodeIfPresent(Int.self, forKey: .ofertas) ?? 0
        segundos = try c.decodeIfPresent(Int.self, forKey: .segundos) ?? 0
        estimadas = try c.decodeIfPresent(Int.self, forKey: .estimadas) ?? 0
        estimadoCent = try c.decodeIfPresent(Int.self, forKey: .estimadoCent) ?? 0
    }
}
