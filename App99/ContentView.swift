import SwiftUI

/// Tela inicial enxuta: painel do turno (ou Iniciar turno), histórico curto e linha do tempo.
/// Ferramentas de teste/depuração ficam em "Mais".
struct ContentView: View {
    @StateObject private var monitor = MonitorExtensao()
    @StateObject private var relatorio = RelatorioStore()
    @ObservedObject private var linha = LinhaDoTempoStore.shared   // um só, compartilhado com o turno
    @Environment(\.scenePhase) private var fase

    var body: some View {
        NavigationStack {
            List {
                PainelTurno(monitor: monitor)

                HistoricoCurto()

                Section {
                    NavigationLink {
                        LinhaDoTempoView(store: linha)
                    } label: {
                        Label("Linha do tempo", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        MaisView(monitor: monitor, relatorio: relatorio)
                    } label: {
                        Label("Mais", systemImage: "ellipsis.circle")
                    }
                }
            }
            .navigationTitle("Apex")
        }
        .task {
            if TurnoStore.shared.atual != nil { Localizacao.shared.ligar() }   // reabriu com turno ativo
            relatorio.pedir()
            linha.pedir()
            await Notificador.pedirPermissao()
        }
        .onChange(of: fase) { nova in
            if nova == .active {
                relatorio.pedir()   // atualiza ao voltar pro app
                linha.pedir()
                SinalApp.naFrente.enviar()
            } else {
                SinalApp.saiu.enviar()
            }
        }
        // Enquanto o app está na tela, a extensão não lê (senão lê a tela do próprio app)
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            if fase == .active && !ModoTeste.telaCheia { SinalApp.naFrente.enviar() }
        }
    }
}

/// Ferramentas e telas antigas (nada foi removido, só saiu da tela inicial).
struct MaisView: View {
    @ObservedObject var monitor: MonitorExtensao
    @ObservedObject var relatorio: RelatorioStore

    var body: some View {
        List {
            Section {
                NavigationLink { AjustesView() } label: {
                    Label("Configuração da moto e voz", systemImage: "gearshape")
                }
                NavigationLink { TesteView() } label: {
                    Label("Testar com um print", systemImage: "photo.on.rectangle")
                }
                NavigationLink { CatalogoTemaView() } label: {
                    Label("Visual do Apex (catálogo)", systemImage: "paintpalette")
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

            RelatorioSections(store: relatorio)
        }
        .navigationTitle("Mais")
    }
}
