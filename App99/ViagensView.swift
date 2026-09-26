import SwiftUI

/// Aba Viagens: corridas e ofertas de todos os turnos do período.
/// Lê os mesmos resumos do TurnoStore (sem cálculo nem armazenamento próprio).
struct ViagensView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @State private var periodo: Periodo = .hoje
    @State private var modo = Modo.corridas

    enum Modo: Hashable { case corridas, ofertas }

    var body: some View {
        // Turnos do período (cada turno conta no dia em que começou, igual ao histórico)
        let resumos = Historico.turnos(turnos.turnos, em: periodo)
            .sorted { $0.inicio > $1.inicio }
            .map { turnos.resumo($0) }
        let dias = Dictionary(grouping: resumos) { Calendar.current.startOfDay(for: $0.turno.inicio) }
            .sorted { $0.key > $1.key }

        List {
            Section {
                Picker("Período", selection: $periodo) {
                    ForEach(Periodo.allCases, id: \.self) { Text($0.nome).tag($0) }
                }
                Picker("Mostrar", selection: $modo) {
                    Text("Corridas").tag(Modo.corridas)
                    Text("Ofertas").tag(Modo.ofertas)
                }
                .pickerStyle(.segmented)
            } footer: {
                if modo == .ofertas {
                    Text("Oferta não é faturamento: é o que apareceu na tela, aceita ou não.")
                }
            }

            if modo == .corridas {
                corridas(dias)
            } else {
                ofertas(dias)
            }
        }
        .navigationTitle("Viagens")
    }

    @ViewBuilder
    private func corridas(_ dias: [(key: Date, value: [ResumoTurno])]) -> some View {
        if dias.allSatisfy({ $0.value.allSatisfy { $0.corridas.isEmpty } }) {
            vazio("Nenhuma corrida neste período.")
        }
        ForEach(dias, id: \.key) { dia in
            let lista = dia.value.flatMap { $0.corridas.reversed() }
            if !lista.isEmpty {
                Section(Datas.curta(dia.key)) {
                    // id da corrida pode repetir entre turnos: identifica pela posição
                    ForEach(lista.indices, id: \.self) { i in
                        NavigationLink { CorridaDetalheView(c: lista[i]) } label: { LinhaCorrida(c: lista[i]) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ofertas(_ dias: [(key: Date, value: [ResumoTurno])]) -> some View {
        if dias.allSatisfy({ $0.value.allSatisfy { $0.ofertas.isEmpty } }) {
            vazio("Nenhuma oferta lida neste período.")
        }
        ForEach(dias, id: \.key) { dia in
            let lista = dia.value.flatMap { $0.ofertas.reversed() }
            if !lista.isEmpty {
                Section(Datas.curta(dia.key)) {
                    ForEach(lista.indices, id: \.self) { i in LinhaOferta(o: lista[i]) }
                }
            }
        }
    }

    private func vazio(_ texto: String) -> some View {
        Text(texto).foregroundStyle(.secondary)
    }
}
