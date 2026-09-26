import SwiftUI

struct PerfilView: View {
    private static let padrao = ConfigMoto()

    @ObservedObject var monitor: MonitorExtensao
    @ObservedObject var relatorio: RelatorioStore
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var turnos = TurnoStore.shared
    @Environment(\.dismiss) private var fechar

    // Mesmas chaves que ConfigMoto.atual e o Narrador leem
    @AppStorage("custoPorKm") private var custoPorKm = padrao.custoPorKm
    @AppStorage("minimoPorKm") private var minimoPorKm = padrao.minimoPorKm
    @AppStorage("bomPorKm") private var bomPorKm = padrao.bomPorKm
    @AppStorage("alertaBuscaKm") private var alertaBuscaKm = padrao.alertaBuscaKm
    @AppStorage("notaMinima") private var notaMinima = padrao.notaMinima
    @AppStorage(Narrador.chaveVelocidade) private var velocidadeFala = Narrador.velocidadePadrao
    @AppStorage(Narrador.chaveFalar) private var falarResultado = false
    @AppStorage("precoLitroPadrao") private var precoLitro = 0.0
    @AppStorage("metaDiaria") private var metaDiaria = 0.0
    @AppStorage(NomesRegioes.chaveAtivo) private var bairros = false

    @State private var confirmarApagarGPS = false
    @State private var confirmarPadrao = false

    var body: some View {
        Form {
            Section("Veículo") {
                campo("Custo por km", $custoPorKm, prefixo: "R$")
                campo("Mínimo por km", $minimoPorKm, prefixo: "R$")
                campo("Bom por km", $bomPorKm, prefixo: "R$")
                campo("Alerta de busca", $alertaBuscaKm, sufixo: "km")
                campo("Nota mínima do passageiro", $notaMinima)
                Button("Restaurar padrões") { confirmarPadrao = true }
            }

            Section("Combustível") {
                campo("Preço padrão do litro", $precoLitro, prefixo: "R$", casas: 3)
            }

            Section("Metas") {
                campo("Meta diária", $metaDiaria, prefixo: "R$")
            }

            Section("Voz") {
                Toggle("Falar resultado da oferta", isOn: $falarResultado)
                HStack {
                    Image(systemName: "tortoise").foregroundStyle(Tema.textoSecundario)
                    Slider(value: $velocidadeFala, in: 0.35...0.60, step: 0.01)
                    Image(systemName: "hare").foregroundStyle(Tema.textoSecundario)
                }
                Button("Ouvir exemplo") {
                    Task { await Narrador.shared.falar("Corrida boa. 2 reais e 60 por quilômetro. Lucro de 9 reais e 40. 5,2 quilômetros no total.") }
                }
            }

            Section("Leitura") {
                BotaoIniciarLeitura()
                NavigationLink {
                    List { StatusExtensaoView(monitor: monitor) }.navigationTitle("Status da leitura")
                } label: {
                    LabeledContent("Status", value: monitor.ligada ? "Ligada" : "Sem sinal")
                }
            }

            Section("Dados") {
                let arquivos = Self.arquivos
                ShareLink(items: arquivos) {
                    Label("Exportar dados", systemImage: "square.and.arrow.up")
                }
                .disabled(arquivos.isEmpty)
                Button("Apagar trajetos de GPS", role: .destructive) { confirmarApagarGPS = true }
            }

            Section {
                Toggle("Identificar bairros", isOn: $bairros)
                    .onChange(of: bairros) { ligado in
                        if !ligado { NomesRegioes.shared.apagarNomes() }
                        NomesRegioes.shared.objectWillChange.send()
                    }
            } header: {
                Text("Privacidade")
            } footer: {
                Text("Envia à Apple o centro aproximado de cada região (~1 km) para obter o nome do bairro.")
            }

            Section {
                LabeledContent("Versão", value: Self.versao)
            }

            Section("Diagnóstico") {
                NavigationLink("Testar com um print") { TesteView() }
                NavigationLink("Linha do tempo técnica") { LinhaDoTempoView(store: linha, titulo: "Linha do tempo técnica") }
                NavigationLink("Relatório da leitura") {
                    List { RelatorioSections(store: relatorio) }.navigationTitle("Relatório da leitura")
                }
            }
        }
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("OK") { fechar() } }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { AjustesCompartilhados.enviar() }   // a leitura usa os ajustes na hora, se estiver ligada
        .onChange(of: falarResultado) { _ in AjustesCompartilhados.enviar() }
        .confirmationDialog("Apagar os trajetos de GPS dos turnos encerrados?", isPresented: $confirmarApagarGPS,
                            titleVisibility: .visible) {
            Button("Apagar trajetos", role: .destructive) { turnos.apagarTrajetos() }
        }
        .confirmationDialog("Restaurar os valores padrão do veículo e da voz?", isPresented: $confirmarPadrao,
                            titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) {
                custoPorKm = Self.padrao.custoPorKm
                minimoPorKm = Self.padrao.minimoPorKm
                bomPorKm = Self.padrao.bomPorKm
                alertaBuscaKm = Self.padrao.alertaBuscaKm
                notaMinima = Self.padrao.notaMinima
                velocidadeFala = Narrador.velocidadePadrao
                falarResultado = false
            }
        }
    }

    static var versao: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static var arquivos: [URL] {
        guard let pasta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let lista = try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)
        else { return [] }
        return lista.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func campo(_ titulo: String, _ valor: Binding<Double>, prefixo: String? = nil, sufixo: String? = nil,
                       casas: Int = 2) -> some View {
        LabeledContent(titulo) {
            HStack(spacing: 4) {
                if let prefixo { Text(prefixo).foregroundStyle(Tema.textoSecundario) }
                TextField("0", value: valor,
                          format: .number.precision(.fractionLength(casas)).locale(Locale(identifier: "pt_BR")))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                if let sufixo { Text(sufixo).foregroundStyle(Tema.textoSecundario) }
            }
        }
    }
}
