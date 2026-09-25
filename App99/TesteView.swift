import SwiftUI
import PhotosUI

/// Testa o leitor com um print da galeria: mostra o texto do OCR, os valores e o resultado, e fala a frase.
struct TesteView: View {
    @State private var item: PhotosPickerItem?
    @State private var imagem: UIImage?
    @State private var modoExtensao = true
    @State private var telaCheia = false

    @State private var lendo = false
    @State private var linhas: [String] = []
    @State private var oferta: OfertaCorrida?
    @State private var analise: AnaliseCorrida?
    @State private var erro: String?

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $item, matching: .images) {
                    Label("Escolher print da galeria", systemImage: "photo")
                }
                Toggle("OCR rápido (igual à extensão)", isOn: $modoExtensao)
                if let imagem {
                    Image(uiImage: imagem)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                    Button {
                        telaCheia = true
                    } label: {
                        Label("Mostrar em tela cheia", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            } footer: {
                Text("Com a leitura da tela ligada, \"Mostrar em tela cheia\" deixa a extensão ler este print como se fosse a 99. Toque no print pra fechar.")
            }

            if lendo {
                Section { ProgressView("Lendo o print…") }
            }

            if let erro {
                Section("Erro") {
                    Text(erro).foregroundStyle(.red)
                }
            }

            if let analise {
                Section("Resultado") {
                    Text(analise.veredito.falado)
                        .font(.title2.bold())
                        .foregroundStyle(cor(analise.veredito))
                    LabeledContent("Ganho por km", value: Formato.reais(analise.ganhoPorKm))
                    LabeledContent("Km total", value: Formato.km(analise.kmTotal))
                    LabeledContent("Custo estimado", value: Formato.reais(analise.custoEstimado))
                    LabeledContent("Lucro", value: Formato.reais(analise.lucro))
                    LabeledContent("Lucro por km", value: Formato.reais(analise.lucroPorKm))
                    if let porHora = analise.ganhoPorHora {
                        LabeledContent("Lucro por hora", value: Formato.reais(porHora))
                    }
                    Text(analise.fraseFalada)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await Narrador.shared.falar(analise.fraseFalada) }
                    } label: {
                        Label("Falar de novo", systemImage: "speaker.wave.2")
                    }
                }
            }

            if let oferta {
                Section("Valores extraídos") {
                    LabeledContent("Valor", value: Formato.reais(oferta.valor))
                    LabeledContent("Busca", value: Formato.km(oferta.kmAtePassageiro))
                    LabeledContent("Viagem", value: Formato.km(oferta.kmViagem))
                    LabeledContent("Min até passageiro", value: oferta.minAtePassageiro.map { "\($0) min" } ?? "—")
                    LabeledContent("Min de viagem", value: oferta.minViagem.map { "\($0) min" } ?? "—")
                }
            }

            if !linhas.isEmpty {
                Section("Texto bruto do OCR") {
                    Text(linhas.joined(separator: "\n"))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Testar print")
        .fullScreenCover(isPresented: $telaCheia) {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .onTapGesture { telaCheia = false }
            }
        }
        .onChange(of: item) { novo in
            Task { await carregar(novo) }
        }
        .onChange(of: modoExtensao) { _ in
            Task { await analisar() }
        }
    }

    @MainActor
    private func carregar(_ item: PhotosPickerItem?) async {
        guard let item,
              let dados = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: dados) else {
            erro = item == nil ? nil : "Não consegui abrir a imagem."
            return
        }
        imagem = img
        await analisar()
    }

    @MainActor
    private func analisar() async {
        guard let imagem else { return }
        lendo = true
        erro = nil
        linhas = []
        oferta = nil
        analise = nil

        let leitor = LeitorOferta99(nivel: modoExtensao ? .fast : .accurate)
        do {
            linhas = try await leitor.reconhecerTexto(em: imagem)
            let o = try ParserOferta99.extrair(de: linhas)
            let a = CalculadoraCorrida(config: .atual).analisar(o)   // valores da tela de Ajustes
            oferta = o
            analise = a
            lendo = false
            await Narrador.shared.falarSeLigado(a.fraseFalada)
        } catch {
            lendo = false
            erro = error.localizedDescription
        }
    }

    private func cor(_ v: Veredito) -> Color {
        switch v {
        case .boa:       return .green
        case .aceitavel: return .orange
        case .ruim:      return .red
        }
    }
}
