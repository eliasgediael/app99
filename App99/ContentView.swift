import SwiftUI

enum Aba: Hashable { case turno, viagens, mapa, atividade, analises }

/// O que o Mapa deve mostrar quando outra tela manda abrir (corrida → mapa, hora → mapa).
struct FocoMapa: Equatable {
    var turno: UUID
    var intervalo: DateInterval?
    var corrida: Int?
}

@MainActor
final class Navegacao: ObservableObject {
    static let shared = Navegacao()

    @Published var aba: Aba = .turno
    @Published var perfilAberto = false
    @Published var focoMapa: FocoMapa?

    /// Abre a aba Mapa já focada (fecha folhas abertas por cima).
    func abrirMapa(turno: UUID, intervalo: DateInterval? = nil, corrida: Int? = nil) {
        perfilAberto = false
        focoMapa = FocoMapa(turno: turno, intervalo: intervalo, corrida: corrida)
        aba = .mapa
    }
}

/// O ciclo de vida (GPS ao reabrir, pedidos à extensão, aviso "app na frente") fica AQUI, na raiz,
/// pra valer igual em qualquer aba aberta.
struct ContentView: View {
    @StateObject private var monitor = MonitorExtensao()
    @StateObject private var relatorio = RelatorioStore()
    @ObservedObject private var nav = Navegacao.shared
    @ObservedObject private var linha = LinhaDoTempoStore.shared   // um só, compartilhado com o turno
    @Environment(\.scenePhase) private var fase

    var body: some View {
        TabView(selection: $nav.aba) {
            NavigationStack {
                PainelTurno(monitor: monitor)
                    .navigationTitle("Turno")
                    .estiloAba(nav)
            }
            .tabItem { Label("Turno", systemImage: "speedometer") }
            .tag(Aba.turno)

            NavigationStack {
                ViagensView().estiloAba(nav)
            }
            .tabItem { Label("Viagens", systemImage: "list.bullet") }
            .tag(Aba.viagens)

            NavigationStack {
                MapaAbaView().estiloAba(nav)
            }
            .tabItem { Label("Mapa", systemImage: "map") }
            .tag(Aba.mapa)

            NavigationStack {
                AtividadeView().estiloAba(nav)
            }
            .tabItem { Label("Atividade", systemImage: "clock") }
            .tag(Aba.atividade)

            NavigationStack {
                AnalisesView().estiloAba(nav)
            }
            .tabItem { Label("Análises", systemImage: "chart.bar") }
            .tag(Aba.analises)
        }
        .tint(Tema.positivo)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $nav.perfilAberto) {
            NavigationStack { PerfilView(monitor: monitor, relatorio: relatorio) }
                .tint(Tema.primaria)
        }
        .task {
            if TurnoStore.shared.atual != nil { Localizacao.shared.ligar() }   // reabriu com turno ativo
            Reprocessamento.executarSeNecessario()
            relatorio.pedir()
            linha.pedir()
            await Notificador.pedirPermissao()
        }
        .onChange(of: fase) { nova in
            if nova == .active {
                relatorio.pedir()
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

extension View {
    /// Perfil no canto superior direito e barra de abas translúcida.
    func estiloAba(_ nav: Navegacao) -> some View {
        toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { nav.perfilAberto = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Perfil")
                }
            }
    }
}
