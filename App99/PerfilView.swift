import SwiftUI

/// Perfil: configurações, dados, privacidade e ferramentas. Tudo que antes ficava em "Mais" continua aqui.
struct PerfilView: View {
    @ObservedObject var monitor: MonitorExtensao
    @ObservedObject var relatorio: RelatorioStore
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @AppStorage(NomesRegioes.chaveAtivo) private var bairros = false
    @AppStorage("metaDiaria") private var metaDiaria = 0.0
    @AppStorage("precoLitroPadrao") private var precoLitro = 0.0
    @Environment(\.dismiss) private var fechar

    var body: some View {
        List {
            Section {
                NavigationLink { AjustesView() } label: {
                    rotulo("Custos e critérios da moto", "gearshape", nil)
                }
                NavigationLink { CombustivelMetaView() } label: {
                    rotulo("Combustível e meta", "fuelpump", resumoCombustivel)
                }
            } header: {
                Text("Moto e decisão")
            }

            Section("Voz") {
                NavigationLink { VozView() } label: {
                    rotulo("Voz do resultado", "speaker.wave.2", Narrador.vozLigada ? "ligada" : "desligada")
                }
            }

            Section {
                BotaoIniciarLeitura()
                NavigationLink {
                    List { StatusExtensaoView(monitor: monitor) }.navigationTitle("Status da leitura")
                } label: {
                    rotulo("Status da leitura (ao vivo)", "waveform", monitor.ligada ? "ligada" : nil)
                }
            } header: {
                Text("Leitura da tela")
            } footer: {
                Text("\"Iniciar leitura\" liga só a leitura das ofertas, sem turno e sem GPS. Pra testar em casa: ligue a leitura, abra Ferramentas → Testar com um print e toque em \"Mostrar em tela cheia\".")
            }

            Section("Dados") {
                NavigationLink { DadosView() } label: {
                    rotulo("Exportar, retenção e exclusão", "externaldrive", nil)
                }
                NavigationLink { RelatorioLeituraView(relatorio: relatorio) } label: {
                    rotulo("Relatório da leitura (antigo)", "doc.text", nil)
                }
            }

            Section {
                Toggle(isOn: $bairros) {
                    rotulo("Identificar bairros e regiões", "mappin.and.ellipse", nil)
                }
                .onChange(of: bairros) { ligado in
                    if !ligado { NomesRegioes.shared.apagarNomes() }
                    NomesRegioes.shared.objectWillChange.send()
                }
            } header: {
                Text("Privacidade")
            } footer: {
                Text(bairros
                     ? "Ligado: para dar nome às regiões das Análises, o Apex envia ao serviço de mapas da Apple o CENTRO APROXIMADO de cada região (célula de ~1 km), não o seu trajeto. Os nomes ficam guardados no iPhone. Desligue para parar e apagar os nomes."
                     : "Desligado: nenhuma coordenada sai do iPhone e as regiões aparecem por código (ex.: Região 6u35t1). Se ligar, o centro aproximado de cada região (~1 km) é enviado à Apple para descobrir o nome do bairro.")
            }

            Section("Ferramentas") {
                NavigationLink { TesteView() } label: {
                    rotulo("Testar com um print", "photo.on.rectangle", nil)
                }
                NavigationLink { LinhaDoTempoView(store: linha, titulo: "Linha do tempo técnica") } label: {
                    rotulo("Linha do tempo técnica", "list.bullet.rectangle", nil)
                }
                NavigationLink { CatalogoTemaView() } label: {
                    rotulo("Visual do Apex (catálogo)", "paintpalette", nil)
                }
            }

            Section {
            } footer: {
                Text("Apex · seus dados ficam só neste iPhone. Sem conta, sem nuvem, sem servidor.")
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("OK") { fechar() } }
    }

    private var resumoCombustivel: String {
        var partes: [String] = []
        if precoLitro > 0 {
            partes.append(String(format: "R$ %.3f/L", precoLitro).replacingOccurrences(of: ".", with: ","))
        }
        if metaDiaria > 0 { partes.append("meta " + Formato.reais(metaDiaria)) }
        return partes.joined(separator: " · ")
    }

    private func rotulo(_ titulo: String, _ icone: String, _ valor: String?) -> some View {
        HStack {
            Label(titulo, systemImage: icone)
            Spacer()
            if let valor, !valor.isEmpty {
                Text(valor).font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            }
        }
    }
}

// MARK: - Combustível e meta

struct CombustivelMetaView: View {
    @AppStorage("metaDiaria") private var metaDiaria = 0.0
    @AppStorage("precoLitroPadrao") private var precoLitro = 0.0

    private let reais = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR"))
    private let preco = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3)).locale(Locale(identifier: "pt_BR"))

    var body: some View {
        Form {
            Section {
                LabeledContent("Preço padrão do litro (R$)") {
                    TextField("6,290", value: $precoLitro, format: preco)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                }
            } header: {
                Text("Combustível")
            } footer: {
                Text("Já vem preenchido ao registrar um abastecimento (dá pra mudar na hora). 0 = sem preço padrão. Não muda nenhum cálculo de corrida: o custo por km continua em Custos e critérios da moto.")
            }
            Section {
                LabeledContent("Meta diária (R$)") {
                    TextField("150,00", value: $metaDiaria, format: reais)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                }
            } header: {
                Text("Meta")
            } footer: {
                Text("Aparece no Turno como progresso do faturamento CONFIRMADO do dia. Estimado não conta. 0 = sem meta.")
            }
        }
        .navigationTitle("Combustível e meta")
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Dados

/// Exportar, o que fica guardado e por quanto tempo, e o que dá pra apagar com segurança.
struct DadosView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @State private var confirmarApagarGPS = false
    @State private var apagados: Int?

    private var arquivos: [URL] {
        guard let pasta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let lista = try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)
        else { return [] }
        return lista.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        let arquivos = self.arquivos
        List {
            Section {
                if arquivos.isEmpty {
                    Text("Nenhum dado ainda.").foregroundStyle(Tema.textoSecundario)
                } else {
                    ShareLink(items: arquivos) {
                        Label("Exportar todos os dados (\(arquivos.count) arquivos)", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Exportar")
            } footer: {
                Text("Turnos, custos, linha do tempo e trajetos em JSON. Também aparecem no app Arquivos → No meu iPhone → Apex, e no iTunes/Dispositivos Apple pelo cabo. Servem de backup: guarde uma cópia antes de trocar de celular.")
            }

            Section {
                LabeledContent("Turnos e custos", value: "até você apagar")
                LabeledContent("Linha do tempo", value: "90 dias")
                LabeledContent("Trajetos de GPS", value: "90 dias")
                LabeledContent("Nomes de bairros", value: "só se ativado")
            } header: {
                Text("O que fica guardado")
            } footer: {
                Text("Tudo fica só neste iPhone. O Apex não tem conta, nuvem nem servidor. O que passa do prazo é apagado sozinho.")
            }

            Section {
                Button("Apagar trajetos de GPS", role: .destructive) { confirmarApagarGPS = true }
                if let n = apagados {
                    Text(n == 0 ? "Não havia trajetos para apagar." : "\(n) trajeto\(n == 1 ? "" : "s") apagado\(n == 1 ? "" : "s").")
                        .foregroundStyle(Tema.textoSecundario)
                }
            } header: {
                Text("Apagar")
            } footer: {
                Text("Apaga os trajetos dos turnos encerrados (o do turno ativo fica). Faturamento e corridas continuam; km, R$/km e mapas desses turnos ficam em branco.\n\nPara apagar TUDO, apague o app Apex do iPhone: é o único jeito de apagar junto os dados que a leitura da tela guarda por conta própria (senão ela devolveria os eventos ao app).")
            }
        }
        .navigationTitle("Dados")
        .confirmationDialog("Apagar os trajetos de GPS dos turnos encerrados?", isPresented: $confirmarApagarGPS, titleVisibility: .visible) {
            Button("Apagar trajetos", role: .destructive) { apagados = turnos.apagarTrajetos() }
        } message: {
            Text("Não dá pra desfazer. Exporte antes se quiser guardar.")
        }
    }
}

// MARK: - Relatório antigo

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
