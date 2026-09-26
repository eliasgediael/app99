import SwiftUI

extension Confianca {
    var cor: Color {
        switch self {
        case .confirmado:    return Tema.positivo
        case .estimado:      return Tema.atencao
        case .indeterminado: return Tema.neutro
        }
    }
}

enum Duracao {
    /// 4h52 · 18 min
    static func curta(_ s: TimeInterval) -> String {
        let min = Int(s / 60)
        return min < 60 ? "\(min) min" : String(format: "%dh%02d", min / 60, min % 60)
    }
}
