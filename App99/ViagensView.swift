import SwiftUI

/// Aba Viagens: histórico de corridas (e ofertas) do período, agrupado por dia.
/// Lê os mesmos resumos do TurnoStore (sem cálculo nem armazenamento próprio).
/// Cada turno conta no dia em que começou, igual a Análises.
struct ViagensView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @State private var periodo: Periodo = .hoje
    @State private var modo = Modo.corridas

    enum Modo: Hashable { case corridas, ofertas }
    static let periodos: [Periodo] = [.hoje, .ontem, .ultimos7, .ultimos30]

    /// Corrida + o resumo do turno dela (o detalhe usa o turno pro mapa).
    struct Item {
        let r: ResumoTurno
        let c: CorridaAnalisada
    }

    struct Dia: Identifiable {
        let id: Date
        var resumos: [ResumoTurno]
        var corridas: [Item] { resumos.flatMap { r in r.corridas.reversed().map { Item(r: r, c: $0) } } }
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
            if modo == .corridas {
                corridas(dias, vazio: a.corridasFeitas == 0 && dias.allSatisfy { $0.corridas.isEmpty })
            } else {
                ofertas(dias, vazio: a.ofertas == 0)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tema.fundo.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { filtros(a) }
        .navigationTitle("Viagens")
    }

    // MARK: Filtros e total do período

    private func filtros(_ a: ResumoAgregado) -> some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espaco.s) {
                    ForEach(Self.periodos, id: \.self) { p in
                        ChipFiltro(titulo: p.nome, ativo: periodo == p) { periodo = p }
                    }
                }
                .padding(.horizontal, Espaco.margem)
            }
            Picker("Mostrar", selection: $modo) {
                Text("Corridas").tag(Modo.corridas)
                Text("Ofertas").tag(Modo.ofertas)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Espaco.margem)

            Group {
                if modo == .corridas {
                    Text("\(Formato.reais(a.confirmado)) confirmado · " + PainelTurno.corridas(a.corridasConfirmadas)
                         + (a.corridasEstimadas > 0 ? " · \(a.corridasEstimadas) estimada\(a.corridasEstimadas == 1 ? "" : "s")" : ""))
                } else {
                    Text("Oferta · não é faturamento. \(a.ofertas) recebida\(a.ofertas == 1 ? "" : "s"), \(a.ofertasAceitas) aceita\(a.ofertasAceitas == 1 ? "" : "s").")
                }
            }
            .font(Tipo.legenda)
            .foregroundStyle(Tema.textoSecundario)
            .padding(.horizontal, Espaco.margem)
        }
        .padding(.vertical, Espaco.s)
        .background(Tema.fundo)
    }

    // MARK: Corridas

    @ViewBuilder
    private func corridas(_ dias: [Dia], vazio: Bool) -> some View {
        if vazio {
            EstadoVazio(icone: "car", titulo: "Nenhuma corrida",
                        texto: "As corridas dos turnos deste período aparecem aqui.")
                .listRowBackground(Tema.fundo)
                .listRowSeparator(.hidden)
        }
        ForEach(dias) { dia in
            let lista = dia.corridas
            if !lista.isEmpty {
                Section {
                    ForEach(lista.indices, id: \.self) { i in   // id da corrida pode repetir entre turnos
                        NavigationLink { CorridaDetalheView(c: lista[i].c, r: lista[i].r) } label: {
                            LinhaCorrida(c: lista[i].c)
                        }
                        .listRowBackground(Tema.fundo)
                        .listRowSeparatorTint(Tema.linha)
                    }
                } header: {
                    cabecalhoDia(dia.id, resumo: resumoDia(dia))
                }
            }
        }
    }

    private func resumoDia(_ dia: Dia) -> String {
        let a = ResumoAgregado(resumos: dia.resumos)
        return "\(Formato.reais(a.confirmado)) · " + PainelTurno.corridas(a.corridasConfirmadas)
    }

    // MARK: Ofertas

    @ViewBuilder
    private func ofertas(_ dias: [Dia], vazio: Bool) -> some View {
        if vazio {
            EstadoVazio(icone: "tag", titulo: "Nenhuma oferta lida",
                        texto: "As ofertas aparecem aqui quando a leitura da tela está ligada durante o turno.")
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
                    let aceitas = lista.filter { $0.resultado == .aceita }.count
                    cabecalhoDia(dia.id, resumo: "\(lista.count) oferta\(lista.count == 1 ? "" : "s") · \(aceitas) aceita\(aceitas == 1 ? "" : "s")")
                }
            }
        }
    }

    private func cabecalhoDia(_ dia: Date, resumo: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            RotuloSecao(Datas.curta(dia))
            Spacer()
            Text(resumo)
                .font(Tipo.legenda.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
        }
        .padding(.vertical, Espaco.xs)
        .background(Tema.fundo)
    }
}
