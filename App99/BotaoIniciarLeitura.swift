import SwiftUI
import ReplayKit

/// Abre o seletor de transmissão do sistema já apontando pra nossa extensão.
/// O ícone é o próprio RPSystemBroadcastPickerView; tocar no texto dispara o botão interno dele.
struct BotaoIniciarLeitura: View {
    @State private var seletor = SeletorTransmissao()

    var body: some View {
        Button {
            seletor.abrir()
        } label: {
            HStack(spacing: 12) {
                SeletorView(picker: seletor.picker)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Iniciar leitura da tela")
                        .font(.headline)
                    Text("Grava a tela e analisa as ofertas da 99")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
final class SeletorTransmissao {
    /// Lê o ID de dentro do .appex instalado: o Sideloadly pode trocar os IDs
    /// (ex.: com.elias.app99.XXXXXXXXXX.broadcast), e aí o fixo não casaria.
    static let idExtensao: String = {
        if let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Broadcast.appex"),
           let id = Bundle(url: url)?.bundleIdentifier {
            return id
        }
        return "com.elias.app99.broadcast"
    }()

    let picker: RPSystemBroadcastPickerView = {
        let p = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        p.preferredExtension = SeletorTransmissao.idExtensao
        p.showsMicrophoneButton = false
        p.tintColor = .systemRed
        return p
    }()

    func abrir() {
        for case let botao as UIButton in picker.subviews {
            botao.sendActions(for: .touchUpInside)
        }
    }
}

private struct SeletorView: UIViewRepresentable {
    let picker: RPSystemBroadcastPickerView

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { picker }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
