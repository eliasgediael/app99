import SwiftUI

/// Conta os sinais que a extensão manda enquanto o app está aberto.
@MainActor
final class MonitorExtensao: ObservableObject {
    @Published private(set) var contagem: [SinalExtensao: Int] = [:]
    @Published private(set) var ultimoSinalEm: Date?

    var ligada: Bool {
        (contagem[.iniciou] ?? 0) > (contagem[.terminou] ?? 0)
    }

    init() {
        let centro = CFNotificationCenterGetDarwinNotifyCenter()
        let observador = Unmanaged.passUnretained(self).toOpaque()   // vive enquanto o app vive (@StateObject na raiz)

        for sinal in SinalExtensao.allCases {
            CFNotificationCenterAddObserver(centro, observador, { _, observador, nome, _, _ in
                guard let observador, let nome else { return }
                let monitor = Unmanaged<MonitorExtensao>.fromOpaque(observador).takeUnretainedValue()
                let bruto = nome.rawValue as String
                Task { @MainActor in monitor.recebeu(bruto) }
            }, sinal.nome.rawValue, nil, .deliverImmediately)
        }
    }

    private func recebeu(_ nome: String) {
        guard let sinal = SinalExtensao.allCases.first(where: { $0.nome.rawValue as String == nome }) else { return }
        contagem[sinal, default: 0] += 1
        ultimoSinalEm = Date()
        if sinal == .iniciou || sinal == .pedirAjustes {
            AjustesCompartilhados.enviar()
        }
    }

    func quantos(_ s: SinalExtensao) -> Int { contagem[s] ?? 0 }
}

struct StatusExtensaoView: View {
    @ObservedObject var monitor: MonitorExtensao

    var body: some View {
        LabeledContent("Extensão") {
            if monitor.quantos(.iniciou) == 0 {
                Text("nenhum sinal ainda").foregroundStyle(.secondary)
            } else if monitor.ligada {
                Text("ligada").foregroundStyle(.green)
            } else {
                Text("desligada").foregroundStyle(.orange)
            }
        }
        if monitor.quantos(.iniciou) > 0 {
            LabeledContent("Seus ajustes") {
                if monitor.quantos(.ajustesRecebidos) > 0 {
                    Text("recebidos").foregroundStyle(.green)
                } else {
                    Text("não chegaram (usando padrão)").foregroundStyle(.orange)
                }
            }
        }
        LabeledContent("Frames lidos", value: "\(monitor.quantos(.leitura))")
        if monitor.quantos(.falhaOCR) > 0 {
            LabeledContent("Erros de OCR", value: "\(monitor.quantos(.falhaOCR))")
        }
        LabeledContent("Ofertas encontradas", value: "\(monitor.quantos(.oferta))")
        LabeledContent("Avisos enviados", value: "\(monitor.quantos(.aviso))")
        if let em = monitor.ultimoSinalEm {
            LabeledContent("Último sinal", value: em.formatted(date: .omitted, time: .standard))
        }
    }
}
