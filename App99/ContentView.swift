import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = MonitorExtensao()
    @StateObject private var relatorio = RelatorioStore()
    @Environment(\.scenePhase) private var fase

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

                RelatorioSections(store: relatorio)

                Section {
                    StatusExtensaoView(monitor: monitor)
                } header: {
                    Text("Status da leitura (ao vivo)")
                } footer: {
                    Text("Atualiza enquanto este app está aberto. Pra testar em casa: inicie a leitura, vá em \"Testar com um print\" e toque em \"Mostrar em tela cheia\".")
                }

                Section("Teste") {
                    NavigationLink {
                        TesteView()
                    } label: {
                        Label("Testar com um print", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    NavigationLink {
                        AjustesView()
                    } label: {
                        Label("Configuração da moto e voz", systemImage: "gearshape")
                    }
                } header: {
                    Text("Ajustes")
                }
            }
            .navigationTitle("App 99")
        }
        .task {
            relatorio.pedir()
            await Notificador.pedirPermissao()
        }
        .onChange(of: fase) { nova in
            if nova == .active { relatorio.pedir() }   // atualiza o relatório ao voltar pro app
        }
    }
}
