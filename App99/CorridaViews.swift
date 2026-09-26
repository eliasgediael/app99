import SwiftUI

// MARK: - Corridas que aconteceram

extension ResumoTurno {
    /// Corridas feitas (confirmadas + estimadas), da mais antiga pra mais nova.
    /// Oferta não aceita, cancelamento e registro sem valor não são corrida.
    var feitas: [CorridaAnalisada] {
        corridas.filter { $0.feita }.sorted { ($0.terminoVisto ?? .distantPast) < ($1.terminoVisto ?? .distantPast) }
    }

    var emAndamento: CorridaAnalisada? {
        corridas.last { $0.confianca == nil && $0.estado != .cancelada }
    }
}

extension CorridaAnalisada {
    var feita: Bool { confianca == .confirmado || confianca == .estimado }
    var estimada: Bool { confianca == .estimado }
    var cancelada: Bool { estado == .cancelada }

    var valorTexto: String {
        guard let v = valor.valor else { return "—" }
        return (estimada ? "≈ " : "") + Formato.reais(v)
    }

    var inicioVisto: Date? { aceiteEm ?? aBordoEm ?? encerradaEm }
    var terminoVisto: Date? { fimEm ?? encerradaEm }

    /// "8,2 km · 18 min"
    var resumoCurto: String {
        [kmGPS.valor.map(Formato.km), duracao.valor.map(Duracao.curta)].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Linhas

/// 21:18   R$ 8,70            8,2 km · 18 min
struct LinhaCorrida: View {
    let c: CorridaAnalisada

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(c.terminoVisto.map(Datas.hora) ?? "—")
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
                .frame(width: 46, alignment: .leading)
            Text(c.valorTexto)
                .font(Tipo.valor)
                .monospacedDigit()
                .foregroundStyle(c.estimada ? Tema.atencao : Tema.texto)
            Spacer(minLength: Espaco.s)
            Text(c.resumoCurto)
                .font(Tipo.legenda)
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Oferta: neutra, nunca somada.
struct LinhaOferta: View {
    let o: OfertaAnalisada

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(Datas.hora(o.em))
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoTerciario)
                .frame(width: 46, alignment: .leading)
            Text(Formato.reais(Double(o.valorCent) / 100))
                .font(Tipo.corpo)
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
            Text(Formato.km(o.km))
                .font(Tipo.legenda)
                .monospacedDigit()
                .foregroundStyle(Tema.textoTerciario)
            Spacer(minLength: Espaco.s)
            if o.resultado == .aceita {
                Label("Aceita", systemImage: "checkmark")
                    .font(Tipo.legenda.weight(.semibold))
                    .foregroundStyle(Tema.textoSecundario)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detalhe

struct CorridaDetalheView: View {
    let c: CorridaAnalisada
    var r: ResumoTurno? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                VStack(alignment: .leading, spacing: Espaco.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Espaco.s) {
                        Text(c.valorTexto)
                            .font(Tipo.destaque)
                            .monospacedDigit()
                            .foregroundStyle(c.estimada ? Tema.atencao : Tema.texto)
                        if c.estimada { Selo(texto: "Estimada", cor: Tema.atencao) }
                    }
                    Text(horario)
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                }

                mapa

                GradeMetricas {
                    Metrica(c.kmGPS, "km") { Formato.km($0) }
                    Metrica(c.duracao, "a bordo") { Duracao.curta($0) }
                    Metrica(c.porKm, "por km") { Formato.reais($0) }
                }

                Secao("Etapas") {
                    VStack(alignment: .leading, spacing: 0) {
                        etapa("Aceita", c.aceiteEm, cor: Tema.mapaIndoBuscar, ultima: false)
                        etapa("Passageiro a bordo", c.aBordoEm, cor: Tema.mapaEmCorrida, ultima: false)
                        etapa("Finalizada", c.fimEm ?? c.encerradaEm, cor: Tema.texto, ultima: true)
                    }
                }

                if c.ofertaId != nil {
                    Secao("Oferta") {
                        VStack(spacing: 0) {
                            if let v = c.valorOfertaCent {
                                LinhaMetrica("Valor", Formato.reais(Double(v) / 100))
                                Divisoria()
                            }
                            if let b = c.buscaM {
                                LinhaMetrica("Até o passageiro", Formato.km(Double(b) / 1000))
                                Divisoria()
                            }
                            if let v = c.viagemM {
                                LinhaMetrica("Viagem", Formato.km(Double(v) / 1000))
                            }
                            if let n = c.nota {
                                Divisoria()
                                LinhaMetrica("Nota do passageiro", "★ " + Formato.nota(n))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Corrida")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var horario: String {
        let dia = c.inicioVisto.map(Datas.curta) ?? ""
        let de = c.inicioVisto.map(Datas.hora) ?? "—"
        let ate = c.terminoVisto.map(Datas.hora) ?? "—"
        return "\(dia) · \(de) – \(ate)"
    }

    @ViewBuilder
    private var mapa: some View {
        if let r, r.temGPS, c.origem != nil || c.destino != nil || c.kmGPS.valor != nil {
            Button {
                Navegacao.shared.abrirMapa(turno: r.turno.id, corrida: c.id)
            } label: {
                MapaTurnoView(r: r, corridaFoco: c.id, interativo: false)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.bloco))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir no mapa")
        }
    }

    private func etapa(_ titulo: String, _ quando: Date?, cor: Color, ultima: Bool) -> some View {
        HStack(alignment: .top, spacing: Espaco.m) {
            VStack(spacing: 0) {
                Circle()
                    .fill(quando == nil ? Tema.linha : cor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                if !ultima {
                    Rectangle().fill(Tema.linha).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            Text(titulo)
                .font(Tipo.apoio)
                .foregroundStyle(quando == nil ? Tema.textoTerciario : Tema.texto)
            Spacer()
            Text(quando.map(Datas.hora) ?? "—")
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
        }
        .frame(minHeight: 40, alignment: .top)
    }
}
