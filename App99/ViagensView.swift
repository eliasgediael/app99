import SwiftUI

/// Aba Viagens. Corridas = só corridas feitas (confirmadas e estimadas). Ofertas = o que apareceu na tela.
/// Cada turno conta no dia em que começou, igual a Análises.
struct ViagensView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @State private var periodo: Periodo = .hoje
    @State private var modo = Modo.corridas

    enum Modo: Hashable { case corridas, ofertas }
    static let periodos: [Periodo] = [.hoje, .ontem, .ultimos7, .ultimos30]

    struct Item {
        let r: ResumoTurno
        let c: CorridaAnalisada
    }

    struct Dia: Identifiable {
        let id: Date
        let resumos: [ResumoTurno]
        var corridas: [Item] { resumos.flatMap { r in r.feitas.reversed().map { Item(r: r, c: $0) } } }
        var ofertas: [OfertaAnalisada] { resumos.flatMap { $0.ofertas.reversed() } }
    }

    var body: some View {
        let resumos = Historico.turnos(turnos.turnos, em: periodo)
            .sorted { $0.inicio > $1.inicio }
            .map { turnos.resumo($0) }
        let dias = Dictionary(grouping: resumos) { Calendar.current.startOfDay(for: $0.turno.inicio) }
            .map { Dia(id: $0.key, resumos: $0.value) }
            .sorted { $0.id > $1.id }
        let a = ResumoAgregado(resumos: resumos)

        List {
            cabecalho(a)
                .listRowBackground(Tema.fundo)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Espaco.m, leading: Espaco.margem, bottom: Espaco.l, trailing: Espaco.margem))
            if modo == .corridas {
                corridas(dias)
            } else {
                ofertas(dias)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tema.fundo.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: Espaco.m) {
                Picker("", selection: $modo) {
                    Text("Corridas").tag(Modo.corridas)
                    Text("Ofertas").tag(Modo.ofertas)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Espaco.margem)
                FiltrosChips(opcoes: Self.periodos, nome: { $0.nome }, selecao: $periodo)
            }
            .padding(.vertical, Espaco.s)
            .background(Tema.fundo)
        }
        .navigationTitle("Viagens")
    }

    @ViewBuilder
    private func cabecalho(_ a: ResumoAgregado) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if modo == .corridas {
                Text(Formato.reais(a.confirmado))
                    .font(Tipo.destaque)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                Text(resumoCorridas(a))
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
            } else {
                Text("\(a.ofertas)")
                    .font(Tipo.destaque)
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
                Text("ofertas · \(a.ofertasAceitas) aceitas")
                    .font(Tipo.apoio)
                    .foregroundStyle(Tema.textoSecundario)
            }
        }
    }

    private func resumoCorridas(_ a: ResumoAgregado) -> String {
        var partes = [Datas.corridas(a.corridasConfirmadas)]
        if a.corridasEstimadas > 0 { partes.append("\(a.corridasEstimadas) estimada\(a.corridasEstimadas == 1 ? "" : "s")") }
        if let km = a.km.valor { partes.append(Formato.km(km)) }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private func corridas(_ dias: [Dia]) -> some View {
        if dias.allSatisfy({ $0.corridas.isEmpty }) {
            EstadoVazio(icone: "car", titulo: "Nenhuma corrida")
                .listRowBackground(Tema.fundo)
                .listRowSeparator(.hidden)
        }
        ForEach(dias) { dia in
            let lista = dia.corridas
            if !lista.isEmpty {
                Section {
                    ForEach(lista.indices, id: \.self) { i in
                        NavigationLink { CorridaDetalheView(c: lista[i].c, r: lista[i].r) } label: {
                            LinhaCorrida(c: lista[i].c)
                        }
                        .listRowBackground(Tema.fundo)
                        .listRowSeparatorTint(Tema.linha)
                    }
                } header: {
                    cabecalhoDia(dia.id, Formato.reais(ResumoAgregado(resumos: dia.resumos).confirmado))
                }
            }
        }
    }

    @ViewBuilder
    private func ofertas(_ dias: [Dia]) -> some View {
        if dias.allSatisfy({ $0.ofertas.isEmpty }) {
            EstadoVazio(icone: "tag", titulo: "Nenhuma oferta")
                .listRowBackground(Tema.fundo)
                .listRowSeparator(.hidden)
        }
        ForEach(dias) { dia in
            let lista = dia.ofertas
            if !lista.isEmpty {
                Section {
                    ForEach(lista.indices, id: \.self) { i in
                        LinhaOferta(o: lista[i])
                            .listRowBackground(Tema.fundo)
                            .listRowSeparatorTint(Tema.linha)
                    }
                } header: {
                    cabecalhoDia(dia.id, "\(lista.count)")
                }
            }
        }
    }

    private func cabecalhoDia(_ dia: Date, _ total: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            RotuloSecao(Datas.curta(dia))
            Spacer()
            Text(total)
                .font(Tipo.legenda.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
        }
        .padding(.vertical, Espaco.xs)
        .background(Tema.fundo)
    }
}
