import SwiftUI

/// Corridas = só corridas feitas (confirmadas e estimadas). Ofertas = o que apareceu na tela.
/// Cada turno conta no dia em que começou, igual a Análises.
struct ViagensView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @State private var periodo: Periodo = .ultimos7
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
        let resumos = Historico.turnos(turnos.turnosComRegistro, em: periodo)
            .sorted { $0.inicio > $1.inicio }
            .map { turnos.resumo($0) }
        let dias = Dictionary(grouping: resumos) { Calendar.current.startOfDay(for: $0.turno.inicio) }
            .map { Dia(id: $0.key, resumos: $0.value) }
            .sorted { $0.id > $1.id }
        let nCorridas = dias.reduce(0) { $0 + $1.corridas.count }
        let nOfertas = dias.reduce(0) { $0 + $1.ofertas.count }

        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.l) {
                Segmentos(opcoes: [Modo.corridas, .ofertas],
                          nome: { $0 == .corridas ? "Corridas (\(nCorridas))" : "Ofertas lidas (\(nOfertas))" },
                          selecao: $modo)
                FiltrosChips(opcoes: Self.periodos, nome: { $0.nome }, selecao: $periodo)
                    .padding(.horizontal, -Espaco.margem)

                if resumos.isEmpty {
                    EstadoVazio(icone: "car", titulo: "Nenhum turno \(Self.noPeriodo(periodo))")
                } else if modo == .corridas {
                    if nCorridas == 0 {
                        EstadoVazio(icone: "car", titulo: "Nenhuma corrida")
                    }
                    ForEach(dias) { dia in
                        let lista = dia.corridas
                        if !lista.isEmpty {
                            cartaoDia(dia.id, total: Formato.reais(ResumoAgregado(resumos: dia.resumos).confirmado)) {
                                ForEach(lista.indices, id: \.self) { i in
                                    NavigationLink { CorridaDetalheView(c: lista[i].c, r: lista[i].r) } label: {
                                        LinhaViagem(c: lista[i].c, ultima: i == lista.count - 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    if nOfertas == 0 {
                        EstadoVazio(icone: "tag", titulo: "Nenhuma oferta")
                    }
                    ForEach(dias) { dia in
                        let lista = dia.ofertas
                        if !lista.isEmpty {
                            cartaoDia(dia.id, total: "\(lista.count)") {
                                ForEach(lista.indices, id: \.self) { i in
                                    LinhaOferta(o: lista[i])
                                    if i < lista.count - 1 { Divisoria() }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.m)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Viagens")
    }

    private func cartaoDia<C: View>(_ dia: Date, total: String, @ViewBuilder conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                RotuloSecao(Datas.curta(dia))
                Spacer()
                Text(total)
                    .font(Tipo.legenda.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
            }
            Cartao(espaco: 14) { conteudo() }
        }
    }

    static func noPeriodo(_ p: Periodo) -> String {
        switch p {
        case .hoje:      return "hoje"
        case .ontem:     return "ontem"
        case .ultimos7:  return "nos últimos 7 dias"
        case .ultimos30: return "nos últimos 30 dias"
        case .semana:    return "nesta semana"
        case .mes:       return "neste mês"
        }
    }
}

/// Corrida numa linha do tempo: nó e horário à esquerda, valor e km/tempo à direita.
struct LinhaViagem: View {
    let c: CorridaAnalisada
    let ultima: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Espaco.m) {
            VStack(spacing: 0) {
                Circle()
                    .stroke(c.estimada ? Tema.atencao : Tema.textoTerciario, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                if !ultima {
                    Rectangle().fill(Tema.linha).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.terminoVisto.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                    .font(Tipo.apoio.monospacedDigit())
                    .foregroundStyle(Tema.textoSecundario)
                if let d = c.duracao.valor {
                    Label(Duracao.curta(d), systemImage: "clock")
                        .font(Tipo.legenda.monospacedDigit())
                        .foregroundStyle(Tema.textoTerciario)
                }
            }
            Spacer(minLength: Espaco.s)
            VStack(alignment: .trailing, spacing: 4) {
                Text(c.valorTexto)
                    .font(Tipo.valor)
                    .monospacedDigit()
                    .foregroundStyle(c.estimada ? Tema.atencao : Tema.texto)
                if let km = c.kmGPS.valor {
                    Text(Formato.km(km) + (c.porKm.valor.map { " · " + Formato.reais($0) + "/km" } ?? ""))
                        .font(Tipo.legenda.monospacedDigit())
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
        }
        .padding(.bottom, ultima ? 0 : Espaco.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
