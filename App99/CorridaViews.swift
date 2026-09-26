import SwiftUI

// Peças de corrida e oferta usadas no Turno, no resumo e em Viagens.
// Tudo vem de CorridaAnalisada/OfertaAnalisada (calculadas da linha do tempo): nada é guardado aqui.

// MARK: - Situação da corrida (texto e cor numa linguagem só)

extension CorridaAnalisada {
    var cancelada: Bool { estado == .cancelada }

    /// "Confirmada", "Estimada"…
    var situacao: String {
        if cancelada { return "Cancelada" }
        switch confianca {
        case .confirmado?:    return "Confirmada"
        case .estimado?:      return "Estimada"
        case .indeterminado?: return "Sem confirmação"
        case nil:             return "Em andamento"
        }
    }

    var corSituacao: Color {
        if cancelada { return Tema.textoTerciario }
        switch confianca {
        case .confirmado?:    return Tema.positivo
        case .estimado?:      return Tema.atencao
        case .indeterminado?: return Tema.neutro
        case nil:             return Tema.mapaIndoBuscar
        }
    }

    /// Valor como deve aparecer: confirmado normal, estimado com "≈", o resto sem valor.
    var valorTexto: String {
        if cancelada { return "Cancelada" }
        switch confianca {
        case .confirmado?: return c(valor.valor)
        case .estimado?:   return valor.valor.map { "≈ " + Formato.reais($0) } ?? "Sem valor"
        case .indeterminado?: return "Sem valor"
        case nil:          return valorOfertaCent.map { Formato.reais(Double($0) / 100) + " a confirmar" } ?? "Em andamento"
        }
    }

    private func c(_ v: Double?) -> String { v.map(Formato.reais) ?? "Sem valor" }

    /// Quando começou pra quem olha a lista (aceite; se não foi visto, o embarque).
    var inicioVisto: Date? { aceiteEm ?? aBordoEm ?? encerradaEm }
    /// Quando terminou (tela de fim; se não foi vista, quando foi encerrada).
    var terminoVisto: Date? { fimEm ?? encerradaEm }
}

// MARK: - Linha de corrida

/// Uma corrida numa lista: horário, valor, km, R$/km e duração. O resto fica no detalhe.
struct LinhaCorrida: View {
    let c: CorridaAnalisada

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(c.inicioVisto.map(PainelTurno.hora) ?? "—")
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.valorTexto)
                    .font(Tipo.corpo.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(c.confianca == .confirmado ? Tema.texto
                                     : (c.confianca == .estimado ? Tema.atencao : Tema.textoSecundario))
                if !detalhes.isEmpty {
                    Text(detalhes)
                        .font(Tipo.legenda)
                        .monospacedDigit()
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
            Spacer(minLength: Espaco.s)
            if c.confianca != .confirmado {
                Text(c.situacao)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(c.corSituacao)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detalhes: String {
        var partes: [String] = []
        if let km = c.kmGPS.valor {
            partes.append((c.kmGPS.confianca == .estimado ? "≈ " : "") + Formato.km(km))
        } else if let v = c.viagemM, v > 0 {
            partes.append(Formato.km(Double(v) / 1000) + " (oferta)")
        }
        if c.confianca == .confirmado, let pk = c.porKm.valor { partes.append(Formato.reais(pk) + "/km") }
        if let d = c.duracao.valor { partes.append(Duracao.curta(d)) }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Linha de oferta

/// Oferta é neutra: nunca em menta, nunca somada. Mostra o que a tela mostrou e se foi aceita.
struct LinhaOferta: View {
    let o: OfertaAnalisada

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
            Text(PainelTurno.hora(o.em))
                .font(Tipo.apoio.monospacedDigit())
                .foregroundStyle(Tema.textoSecundario)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(Formato.reais(Double(o.valorCent) / 100))
                    .font(Tipo.corpo)
                    .monospacedDigit()
                    .foregroundStyle(Tema.texto)
                Text(([Formato.km(o.km), o.porKm.map { Formato.reais($0) + "/km" }, o.nota.map { "★ " + Formato.nota($0) }] as [String?])
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Tipo.legenda)
                    .monospacedDigit()
                    .foregroundStyle(Tema.textoSecundario)
            }
            Spacer(minLength: Espaco.s)
            Text(resultado)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(o.resultado == .aceita ? Tema.texto : Tema.textoTerciario)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var resultado: String {
        switch o.resultado {
        case .aceita:    return "Aceita"
        case .naoAceita: return "Não aceita"
        case .emAberto:  return "Na tela"
        }
    }
}

// MARK: - Detalhe da corrida

/// Primeiro o valor e a situação; depois km/tempo, o mapa, as etapas e a oferta.
/// Dados técnicos (ligação oferta↔aceite, motivo, ids) ficam recolhidos no fim.
struct CorridaDetalheView: View {
    let c: CorridaAnalisada
    var r: ResumoTurno? = nil
    @State private var tecnico = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                cabecalho
                aviso
                HStack(alignment: .top, spacing: Espaco.m) {
                    MetricaCompacta(c.kmGPS, rotulo: "km (GPS)") { Formato.km($0) }
                    MetricaCompacta(c.duracao, rotulo: "a bordo") { Duracao.curta($0) }
                    MetricaCompacta(c.porKm, rotulo: "por km") { Formato.reais($0) }
                    MetricaCompacta(c.porHora, rotulo: "por hora") { Formato.reais($0) }
                }
                mapa
                etapas
                oferta
                detalhesTecnicos
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Corrida")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: Espaco.xs) {
            PontoEstado(texto: c.situacao, cor: c.corSituacao)
            Text(c.valorTexto)
                .font(Tipo.destaque)
                .monospacedDigit()
                .foregroundStyle(c.confianca == .confirmado ? Tema.texto
                                 : (c.confianca == .estimado ? Tema.atencao : Tema.textoSecundario))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(horario)
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
        }
    }

    private var horario: String {
        let dia = c.inicioVisto.map(Datas.curta) ?? ""
        let de = c.inicioVisto.map(PainelTurno.hora) ?? "—"
        let ate = c.terminoVisto.map(PainelTurno.hora) ?? "—"
        return "\(dia) · \(de)–\(ate)"
    }

    @ViewBuilder
    private var aviso: some View {
        let motivo = c.motivo.texto(extra: c.falta)
        if c.cancelada {
            Aviso(.informacao, "Corrida cancelada", impacto: "Não entra em nenhum total.")
        } else if c.confianca == .estimado {
            Aviso(.estimativa, "Não deu pra confirmar esta corrida",
                  impacto: "O valor fica fora do faturamento confirmado. " + motivo)
        } else if c.confianca == .indeterminado {
            Aviso(.informacao, "Corrida sem valor identificado",
                  impacto: "Não entra em nenhum total. " + motivo)
        } else if c.confianca == nil {
            Aviso(.informacao, "Corrida em andamento", impacto: "O valor só conta depois da tela de fim da corrida.")
        }
    }

    /// Mapa da corrida (entra na Fase 5).
    @ViewBuilder
    private var mapa: some View {
        EmptyView()
    }

    private var etapas: some View {
        Bloco("Etapas") {
            VStack(alignment: .leading, spacing: 0) {
                etapa("Aceita", c.aceiteEm, vazio: "tela de aceite não vista")
                Divisoria()
                etapa("Passageiro a bordo", c.aBordoEm, vazio: "tela de embarque não vista")
                Divisoria()
                etapa(c.cancelada ? "Cancelada" : "Finalizada", c.cancelada ? c.encerradaEm : c.fimEm,
                      vazio: c.encerradaEm.map { "tela de fim não vista · encerrada às " + PainelTurno.hora($0) } ?? "ainda aberta")
            }
        }
    }

    private func etapa(_ titulo: String, _ quando: Date?, vazio: String) -> some View {
        LinhaMetrica(titulo, texto: Text(quando.map(PainelTurno.hora) ?? vazio)
            .foregroundColor(quando == nil ? Tema.textoTerciario : Tema.texto))
    }

    @ViewBuilder
    private var oferta: some View {
        if c.ofertaId != nil {
            Bloco("Oferta aceita", subtitulo: "o que a 99 mostrou antes do aceite") {
                VStack(spacing: 0) {
                    LinhaMetrica("Valor ofertado", c.valorOfertaCent.map { Formato.reais(Double($0) / 100) } ?? "—")
                    Divisoria()
                    LinhaMetrica("Até o passageiro", c.buscaM.map { Formato.km(Double($0) / 1000) } ?? "—")
                    Divisoria()
                    LinhaMetrica("Viagem", c.viagemM.map { Formato.km(Double($0) / 1000) } ?? "—")
                    if let n = c.nota {
                        Divisoria()
                        LinhaMetrica("Nota do passageiro", "★ " + Formato.nota(n))
                    }
                }
            }
        }
    }

    private var detalhesTecnicos: some View {
        DisclosureGroup(isExpanded: $tecnico) {
            VStack(spacing: 0) {
                LinhaMetrica("Confiança", c.confianca?.nome ?? "aberta")
                Divisoria()
                LinhaMetrica("Oferta ↔ aceite", c.ligacao.nome)
                Divisoria()
                LinhaMetrica("Valor lido na tela de fim", c.valorFinalCent.map { Formato.reais(Double($0) / 100) } ?? "não visto")
                Divisoria()
                LinhaMetrica("Encerrada", c.encerradaEm.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                Divisoria()
                LinhaMetrica("Região do embarque", c.regiaoOrigem.map(NomesRegioes.shared.rotulo) ?? "sem GPS")
                Divisoria()
                LinhaMetrica("Região do desembarque", c.regiaoDestino.map(NomesRegioes.shared.rotulo) ?? "sem GPS/tela de fim")
                Divisoria()
                LinhaMetrica("Número da corrida", "#\(c.id)")
                if c.motivo != .nenhum {
                    Text(c.motivo.texto(extra: c.falta))
                        .font(Tipo.legenda)
                        .foregroundStyle(Tema.textoSecundario)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Espaco.s)
                }
            }
            .padding(.top, Espaco.s)
        } label: {
            RotuloSecao("Detalhes técnicos")
        }
        .tint(Tema.textoSecundario)
    }
}
