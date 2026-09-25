import Foundation

/// Totais de um dia. A extensão acumula; o app guarda de vez e mostra.
struct DiaRelatorio: Codable, Equatable {
    var dia: Int                 // dias desde 01/01/1970 no fuso local
    var faturadoCent = 0         // soma do valor das corridas feitas (bruto)
    var custoCent = 0            // km × custo por km
    var corridas = 0
    var metros = 0
    var ofertas = 0              // ofertas diferentes que apareceram
    var segundos = 0             // tempo com a leitura ligada

    var faturado: Double { Double(faturadoCent) / 100 }
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

    static let canal = CanalDarwin(prefixo: "com.elias.app99.rel", campos: 7)
    /// App → extensão: "me manda os últimos dias"
    static let nomePedido = "com.elias.app99.rel.pedir"

    var campos: [Int] { [dia, faturadoCent, custoCent, corridas, metros, ofertas, segundos] }

    init(dia: Int) { self.dia = dia }

    init?(campos c: [Int]) {
        guard c.count == 7, c[0] > 0 else { return nil }
        dia = c[0]; faturadoCent = c[1]; custoCent = c[2]; corridas = c[3]
        metros = c[4]; ofertas = c[5]; segundos = c[6]
    }
}
