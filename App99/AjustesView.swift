import SwiftUI

/// Edita a ConfigMoto e a velocidade da fala. Grava no UserDefaults com as mesmas
/// chaves que `ConfigMoto.atual` e `Narrador` leem.
struct AjustesView: View {
    private static let padrao = ConfigMoto()

    @AppStorage("custoPorKm") private var custoPorKm = padrao.custoPorKm
    @AppStorage("minimoPorKm") private var minimoPorKm = padrao.minimoPorKm
    @AppStorage("bomPorKm") private var bomPorKm = padrao.bomPorKm
    @AppStorage("alertaBuscaKm") private var alertaBuscaKm = padrao.alertaBuscaKm
    @AppStorage("notaMinima") private var notaMinima = padrao.notaMinima
    @AppStorage(Narrador.chaveVelocidade) private var velocidadeFala = Narrador.velocidadePadrao
    @AppStorage(Narrador.chaveFalar) private var falarResultado = false

    var body: some View {
        Form {
            Section {
                campo("Custo por km (R$)", valor: $custoPorKm)
                campo("Mínimo por km (R$)", valor: $minimoPorKm)
                campo("Bom por km (R$)", valor: $bomPorKm)
                campo("Alerta de busca (km)", valor: $alertaBuscaKm)
            } header: {
                Text("Moto")
            } footer: {
                Text("Custo por km: gasolina + manutenção + desgaste. Abaixo do mínimo por km (valor ÷ km total) = Recusa; acima do bom = Corrida boa. Busca maior que o alerta é avisada na fala.")
            }

            Section {
                campo("Nota mínima", valor: $notaMinima)
            } header: {
                Text("Passageiro")
            } footer: {
                Text("Passageiro com nota abaixo disso = Recusa, mesmo com valor bom.")
            }

            Section {
                Button("Voltar aos valores padrão (moto, passageiro e voz)", role: .destructive) {
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
        .navigationTitle("Moto e decisão")
        .onDisappear { AjustesCompartilhados.enviar() }   // vale na hora se a leitura estiver ligada
        .onChange(of: falarResultado) { _ in AjustesCompartilhados.enviar() }
        .scrollDismissesKeyboard(.interactively)
    }

    private func campo(_ titulo: String, valor: Binding<Double>) -> some View {
        LabeledContent(titulo) {
            TextField(titulo,
                      value: valor,
                      format: .number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR")))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }
}

/// Voz do resultado da oferta. Mesmas chaves do Narrador; manda pra leitura ao sair (como antes).
struct VozView: View {
    @AppStorage(Narrador.chaveVelocidade) private var velocidadeFala = Narrador.velocidadePadrao
    @AppStorage(Narrador.chaveFalar) private var falarResultado = false

    var body: some View {
        Form {
            Section {
                Toggle("Falar resultado", isOn: $falarResultado)
                VStack(alignment: .leading) {
                    Text("Velocidade: \(rotuloVelocidade)")
                    Slider(value: $velocidadeFala, in: 0.35...0.60, step: 0.01) {
                        Text("Velocidade")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
                Button {
                    Task { await Narrador.shared.falar("Corrida boa. 2 reais e 60 por quilômetro. Lucro de 9 reais e 40. 5,2 quilômetros no total.") }
                } label: {
                    Label("Ouvir exemplo", systemImage: "speaker.wave.2")
                }
            } header: {
                Text("Voz")
            } footer: {
                Text("Desligado: só a notificação, sem mexer na sua música.")
            }

        }
        .navigationTitle("Voz")
        .onDisappear { AjustesCompartilhados.enviar() }
        .onChange(of: falarResultado) { _ in AjustesCompartilhados.enviar() }
    }

    private var rotuloVelocidade: String {
        switch velocidadeFala {
        case ..<0.45: return "devagar"
        case ..<0.53: return "normal"
        default:      return "rápida"
        }
    }
}
