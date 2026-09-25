import Foundation

/// Formatação pra tela e notificação (a fala usa `Fala`, em CalculadoraCorrida.swift).
enum Formato {
    private static let moeda: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .currency
        return f
    }()

    static func reais(_ v: Double) -> String {
        moeda.string(from: NSNumber(value: v)) ?? String(format: "R$ %.2f", v)
    }

    static func km(_ v: Double) -> String {
        String(format: "%.1f km", v).replacingOccurrences(of: ".", with: ",")
    }
}
