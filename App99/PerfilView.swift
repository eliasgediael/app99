import SwiftUI

/// Perfil: configurações e ferramentas que antes ficavam em "Mais". Nada removido, só reorganizado.
struct PerfilView: View {
    @ObservedObject var monitor: MonitorExtensao
    @ObservedObject var relatorio: RelatorioStore
    @Environment(\.dismiss) private var fechar

    var body: some View {
        List {
            Section("Moto, decisão e voz") {
                NavigationLink { AjustesView() } label: {
                    Label("Configuração da moto e voz", systemImage: "gearshape")
                }
            }

            Section {
                BotaoIniciarLeitura()
            } header: {
                Text("Só a leitura (sem turno)")
            } footer: {
                Text("Liga só a leitura das ofertas, sem turno e sem GPS. As notificações funcionam igual.")
            }

            Section {
                StatusExtensaoView(monitor: monitor)
            } header: {
                Text("Status da leitura (ao vivo)")
            } footer: {
                Text("Pra testar em casa: ligue a leitura, vá em \"Testar com um print\" e toque em \"Mostrar em tela cheia\".")
            }

            Section("Dados") {
                NavigationLink { RelatorioLeituraView(relatorio: relatorio) } label: {
                    Label("Relatório da leitura (antigo)", systemImage: "doc.text")
                }
            }

            Section("Ferramentas") {
                NavigationLink { TesteView() } label: {
                    Label("Testar com um print", systemImage: "photo.on.rectangle")
                }
                NavigationLink { CatalogoTemaView() } label: {
                    Label("Visual do Apex (catálogo)", systemImage: "paintpalette")
                }
            }
        }
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("OK") { fechar() } }
    }
}

/// O relatório por dia de antes (contado pela extensão). Lógica intacta; só mudou de lugar.
struct RelatorioLeituraView: View {
    @ObservedObject var relatorio: RelatorioStore

    var body: some View {
        List {
            Section {
                Text("Relatório antigo/técnico: soma o que a leitura da tela contou, dia a dia. Pode não bater com Análises, que conta por turno.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            RelatorioSections(store: relatorio)
        }
        .navigationTitle("Relatório da leitura")
    }
}
