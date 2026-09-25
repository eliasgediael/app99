import SwiftUI

struct ContentView: View {
    private let config = ConfigMoto()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BotaoIniciarLeitura()
                } header: {
                    Text("Leitura automática")
                } footer: {
                    Text("Toque, escolha \"App 99\" na lista e \"Iniciar Transmissão\". Depois abra a 99: cada oferta nova é falada e aparece como notificação. Pra parar, toque no indicador de gravação no topo da tela.")
                }

                Section("Teste") {
                    NavigationLink {
                        TesteView()
                    } label: {
                        Label("Testar com um print", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    LabeledContent("Custo por km", value: Formato.reais(config.custoPorKm))
                    LabeledContent("Mínimo por km", value: Formato.reais(config.minimoPorKm))
                    LabeledContent("Bom por km", value: Formato.reais(config.bomPorKm))
                    LabeledContent("Alerta de busca", value: Formato.km(config.alertaBuscaKm))
                } header: {
                    Text("Configuração da moto")
                } footer: {
                    Text("Valores fixos no código (Shared/CalculadoraCorrida.swift).")
                }
            }
            .navigationTitle("App 99")
        }
        .task { await Notificador.pedirPermissao() }
    }
}

/// Formatação pra tela (a fala usa `Fala`, em CalculadoraCorrida.swift).
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
