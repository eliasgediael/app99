import Foundation

// MARK: - Configuração da moto

struct ConfigMoto {
    /// Custo por km rodado. Ex.: gasolina R$ 6,30 / 35 km/L ≈ 0,18
    /// + óleo, pneu, relação, manutenção ≈ 0,12 + desgaste/depreciação ≈ 0,05
    var custoPorKm: Double = 0.35
    /// Abaixo disso (R$/km bruto) = recusa
    var minimoPorKm: Double = 1.80
    /// Acima disso = corrida boa
    var bomPorKm: Double = 2.50
    /// Busca acima disso gera aviso no áudio
    var alertaBuscaKm: Double = 3.0

    /// Lê do UserDefaults (tela de ajustes do app grava aqui); cai no padrão se não tiver.
    static var atual: ConfigMoto {
        let d = UserDefaults.standard
        var c = ConfigMoto()
        if d.object(forKey: "custoPorKm") != nil { c.custoPorKm = d.double(forKey: "custoPorKm") }
        if d.object(forKey: "minimoPorKm") != nil { c.minimoPorKm = d.double(forKey: "minimoPorKm") }
        if d.object(forKey: "bomPorKm") != nil { c.bomPorKm = d.double(forKey: "bomPorKm") }
        if d.object(forKey: "alertaBuscaKm") != nil { c.alertaBuscaKm = d.double(forKey: "alertaBuscaKm") }
        return c
    }
}

// MARK: - Resultado

enum Veredito {
    case boa, aceitavel, ruim

    var falado: String {
        switch self {
        case .boa:       return "Corrida boa"
        case .aceitavel: return "Aceitável"
        case .ruim:      return "Recusa"
        }
    }
}

struct AnaliseCorrida {
    let oferta: OfertaCorrida
    let kmTotal: Double
    let ganhoPorKm: Double
    let custoEstimado: Double
    let lucro: Double
    let lucroPorKm: Double
    let ganhoPorHora: Double?
    let veredito: Veredito
    let buscaLonga: Bool

    /// Frase curta, veredito primeiro — você decide no primeiro segundo.
    var fraseFalada: String {
        var partes = [veredito.falado]
        partes.append("\(Fala.reais(ganhoPorKm)) por quilômetro")
        partes.append("lucro de \(Fala.reais(lucro))")
        partes.append("\(Fala.km(kmTotal)) no total")
        if buscaLonga {
            partes.append("busca de \(Fala.km(oferta.kmAtePassageiro))")
        }
        return partes.joined(separator: ". ") + "."
    }
}

// MARK: - Calculadora

struct CalculadoraCorrida {
    var config: ConfigMoto = .atual

    func analisar(_ o: OfertaCorrida) -> AnaliseCorrida {
        let kmTotal = o.kmAtePassageiro + o.kmViagem
        let ganhoPorKm = kmTotal > 0 ? o.valor / kmTotal : 0
        let custo = kmTotal * config.custoPorKm
        let lucro = o.valor - custo
        let lucroPorKm = kmTotal > 0 ? lucro / kmTotal : 0

        var ganhoPorHora: Double?
        if let a = o.minAtePassageiro, let v = o.minViagem, a + v > 0 {
            ganhoPorHora = lucro / (Double(a + v) / 60)
        }

        let veredito: Veredito
        switch ganhoPorKm {
        case config.bomPorKm...:     veredito = .boa
        case config.minimoPorKm...:  veredito = .aceitavel
        default:                     veredito = .ruim
        }

        return AnaliseCorrida(
            oferta: o,
            kmTotal: kmTotal,
            ganhoPorKm: ganhoPorKm,
            custoEstimado: custo,
            lucro: lucro,
            lucroPorKm: lucroPorKm,
            ganhoPorHora: ganhoPorHora,
            veredito: veredito,
            buscaLonga: o.kmAtePassageiro >= config.alertaBuscaKm
        )
    }
}

// MARK: - Números em formato "falável"
// O sintetizador lê "2,10" como "dois vírgula dez"; aqui vira "2 reais e 10".

enum Fala {
    static func reais(_ valor: Double) -> String {
        let centavosTotais = Int((abs(valor) * 100).rounded())
        let r = centavosTotais / 100
        let c = centavosTotais % 100

        var s: String
        if r == 0 && c > 0 {
            s = "\(c) centavos"
        } else {
            s = r == 1 ? "1 real" : "\(r) reais"
            if c > 0 { s += " e \(c)" }
        }
        return valor < 0 ? "menos \(s)" : s
    }

    private static let formatoKm: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    static func km(_ valor: Double) -> String {
        let n = formatoKm.string(from: NSNumber(value: valor)) ?? String(format: "%.1f", valor)
        return "\(n) quilômetros"
    }
}
