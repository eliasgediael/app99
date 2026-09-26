import SwiftUI

struct ResumoTurnoView: View {
    let turno: Turno
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @Environment(\.dismiss) private var fechar
    @State private var novoCusto = false

    var body: some View {
        let r = turnos.resumo(turno)
        let feitas = r.feitas
        let horas = Horas.porHora([r])
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xxl) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.titulo(turno))
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                    Text(Formato.reais(r.faturamentoConfirmado.valor ?? 0))
                        .font(Tipo.destaque)
                        .monospacedDigit()
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("faturamento confirmado")
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                }

                GradeMetricas {
                    Metrica(r.porHora, "por hora") { Formato.reais($0) }
                    Metrica(r.porKm, "por km") { Formato.reais($0) }
                    Metrica(r.km, "km") { Formato.km($0) }
                    Metrica(Duracao.curta(r.duracao.valor ?? 0), "de turno")
                    Metrica("\(r.corridasConfirmadas)", r.corridasEstimadas > 0 ? "corridas · \(r.corridasEstimadas) ≈" : "corridas")
                    Metrica("\(r.ofertas.filter { $0.resultado == .aceita }.count)/\(r.ofertas.count)", "ofertas aceitas")
                }

                if !r.tempoPorEstado.isEmpty {
                    Secao("Tempo") { BarraEstados(tempos: r.tempoPorEstado) }
                }

                if horas.count > 1 {
                    Secao("Por hora") { GraficoHoras(horas: horas) }
                }

                Secao("Financeiro") { financeiro(r) }

                if !feitas.isEmpty {
                    Secao("Corridas") {
                        VStack(spacing: 0) {
                            ForEach(Array(feitas.indices.reversed()), id: \.self) { i in
                                NavigationLink { CorridaDetalheView(c: feitas[i], r: r) } label: {
                                    LinhaCorrida(c: feitas[i])
                                }
                                .buttonStyle(.plain)
                                if i > 0 { Divisoria() }
                            }
                        }
                    }
                }

                Secao("Abastecimentos", acao: { Button("Adicionar") { novoCusto = true } }) {
                    if r.custos.isEmpty {
                        Text("—").font(Tipo.apoio).foregroundStyle(Tema.textoTerciario)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(r.custos) { c in
                                LinhaMetrica(Datas.hora(c.em) + " · " + c.tipo.nome, Self.detalheCusto(c))
                                if c.id != r.custos.last?.id { Divisoria() }
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    if r.temGPS {
                        Button { Navegacao.shared.abrirMapa(turno: turno.id) } label: {
                            LinhaNavegacao("Ver no mapa", "map", r.km.valor.map(Formato.km) ?? "")
                        }
                        Divisoria()
                    }
                    NavigationLink { OfertasTurnoView(r: r) } label: {
                        LinhaNavegacao("Ofertas", "tag", "\(r.ofertas.count)")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Resumo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("OK") { fechar() } }
        .sheet(isPresented: $novoCusto) { NavigationStack { AbastecimentoView() } }
    }

    private func financeiro(_ r: ResumoTurno) -> some View {
        VStack(spacing: 0) {
            LinhaMetrica("Confirmado", Formato.reais(r.faturamentoConfirmado.valor ?? 0))
            if r.corridasEstimadas > 0 {
                Divisoria()
                LinhaMetrica("Estimado", "≈ " + Formato.reais(r.faturamentoEstimado.valor ?? 0), cor: Tema.atencao)
            }
            Divisoria()
            LinhaMetrica("Abastecimentos", Formato.reais(r.combustivel.valor ?? 0))
            if (r.outrosCustos.valor ?? 0) > 0 {
                Divisoria()
                LinhaMetrica("Outros custos", Formato.reais(r.outrosCustos.valor ?? 0))
            }
            Divisoria()
            LinhaMetrica("Resultado", r.resultado.texto { Formato.reais($0) })
            if r.custoEstimadoPorKm.valor != nil {
                Divisoria()
                LinhaMetrica("Custo da moto", r.custoEstimadoPorKm.texto { Formato.reais($0) })
                Divisoria()
                LinhaMetrica("Resultado operacional", r.resultadoEstimado.texto { Formato.reais($0) })
            }
        }
    }

    private static func detalheCusto(_ c: Custo) -> String {
        [Formato.reais(c.valor), c.litros.map { String(format: "%.2f L", $0).replacingOccurrences(of: ".", with: ",") }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func titulo(_ t: Turno) -> String {
        "\(Datas.curta(t.inicio)) · \(Datas.hora(t.inicio))–\(t.fim.map(Datas.hora) ?? "agora")"
    }
}

/// Ofertas de um turno. Oferta não é faturamento.
struct OfertasTurnoView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            ForEach(r.ofertas.reversed()) { o in
                LinhaOferta(o: o).listRowBackground(Tema.fundo)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tema.fundo.ignoresSafeArea())
        .overlay { if r.ofertas.isEmpty { EstadoVazio(icone: "tag", titulo: "Nenhuma oferta") } }
        .navigationTitle("Ofertas")
        .navigationBarTitleDisplayMode(.inline)
    }
}
