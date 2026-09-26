import SwiftUI

// Componentes antigos, agora ligados aos tokens de Tema.swift. Antes de criar um estilo novo, use/estenda estes.

/// Número principal ("R$ 186,40") com rótulo pequeno embaixo.
struct NumeroDestaque: View {
    let valor: String
    let rotulo: String
    var grande = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(grande ? Tipo.destaque : Tipo.metrica)
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(rotulo)
                .font(Tipo.legenda)
                .foregroundStyle(Tema.textoSecundario)
        }
    }
}

/// Medida com a confiança discreta: número normal se CONFIRMADO; "≈" e laranja se ESTIMADO;
/// "—" se INDETERMINADO. O detalhe (nota) aparece ao tocar.
struct MedidaTexto: View {
    let medida: Medida
    let formatar: (Double) -> String
    @State private var mostrarNota = false

    var body: some View {
        Button {
            mostrarNota.toggle()
        } label: {
            Text(texto)
                .foregroundStyle(medida.confianca == .estimado ? Tema.atencao : Tema.texto)
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .alert(medida.confianca.nome.capitalized, isPresented: $mostrarNota) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Fonte: \(medida.fonte.rawValue)" + (medida.nota.map { "\n\($0)" } ?? ""))
        }
    }

    private var texto: String {
        guard let v = medida.valor, medida.confianca != .indeterminado else { return "—" }
        return (medida.confianca == .estimado ? "≈ " : "") + formatar(v)
    }
}

/// Etiqueta pequena (confiança, origem).
struct Etiqueta: View {
    let texto: String
    let cor: Color

    var body: some View {
        Text(texto)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cor.opacity(0.18), in: Capsule())
            .foregroundStyle(cor)
    }
}

extension Confianca {
    var cor: Color {
        switch self {
        case .confirmado:    return Tema.positivo
        case .estimado:      return Tema.atencao
        case .indeterminado: return Tema.neutro
        }
    }
}

/// Botão grande pras ações principais (Iniciar/Encerrar turno). Telas novas: BotaoPrimario.
struct BotaoGrande: ButtonStyle {
    var cor: Color = Tema.primaria

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(cor.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}

enum Duracao {
    /// 4h52 · 18 min
    static func curta(_ s: TimeInterval) -> String {
        let min = Int(s / 60)
        return min < 60 ? "\(min) min" : String(format: "%dh%02d", min / 60, min % 60)
    }
}
