import SwiftUI
import MapKit

/// Resumo de um turno: primeiro os números principais, depois cada parte numa tela própria.
struct ResumoTurnoView: View {
    let turno: Turno
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @Environment(\.dismiss) private var fechar

    var body: some View {
        conteudo(turnos.resumo(turno))
            .navigationTitle("Resumo do turno")
            .toolbar { Button("OK") { fechar() } }
    }

    private func conteudo(_ r: ResumoTurno) -> some View {
        List {
            principais(r)
            partes(r)
        }
    }

    private func principais(_ r: ResumoTurno) -> some View {
        Section {
            NumeroDestaque(valor: Formato.reais(r.faturamentoConfirmado.valor ?? 0),
                           rotulo: "faturamento confirmado", grande: true)
            if r.corridasEstimadas > 0 {
                Text("+ ≈ \(Formato.reais(r.faturamentoEstimado.valor ?? 0)) estimado em \(r.corridasEstimadas) corrida\(r.corridasEstimadas == 1 ? "" : "s") (fora do total)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Campo("Resultado após custos", r.resultado) { Formato.reais($0) }
            Campo("R$/hora", r.porHora) { Formato.reais($0) }
            Campo("R$/km", r.porKm) { Formato.reais($0) }
            Campo("Distância", r.km) { Formato.km($0) }
            LabeledContent("Duração", value: Duracao.curta(r.duracao.valor ?? 0))
        } header: {
            Text(Self.titulo(turno))
        } footer: {
            Text("Só corridas CONFIRMADAS entram no faturamento. Toque num número pra ver de onde ele vem; \"≈\" = estimado, \"—\" = sem dados.")
        }
    }

    private func partes(_ r: ResumoTurno) -> some View {
        Section {
            NavigationLink { FinanceiroView(r: r) } label: {
                Rotulo("Financeiro", "dollarsign.circle", Formato.reais(r.faturamentoConfirmado.valor ?? 0))
            }
            NavigationLink { DistanciaView(r: r) } label: {
                Rotulo("Distância", "road.lanes", r.km.valor.map(Formato.km) ?? "—")
            }
            NavigationLink { TempoView(r: r) } label: {
                Rotulo("Tempo", "clock", Duracao.curta(r.duracao.valor ?? 0))
            }
            NavigationLink { CorridasView(r: r) } label: {
                Rotulo("Corridas", "figure.wave", "\(r.corridasConfirmadas)" + (r.corridas.count > r.corridasConfirmadas ? " de \(r.corridas.count)" : ""))
            }
            NavigationLink { OfertasView(r: r) } label: {
                Rotulo("Ofertas", "tag", "\(r.ofertas.count)")
            }
            if r.temGPS {
                NavigationLink { MapaTurnoView(r: r).navigationTitle("Mapa") } label: {
                    Rotulo("Mapa", "map", "")
                }
            }
            NavigationLink { CustosView(r: r) } label: {
                Rotulo("Abastecimentos e custos", "fuelpump", r.custos.isEmpty ? "" : "\(r.custos.count)")
            }
            NavigationLink {
                LinhaDoTempoView(store: linha, intervalo: DateInterval(start: turno.inicio, end: turno.fim ?? Date()))
            } label: {
                Rotulo("Linha do tempo", "list.bullet.rectangle", "")
            }
        }
    }

    static func titulo(_ t: Turno) -> String {
        let hora = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        return "\(Datas.curta(t.inicio)) · \(hora(t.inicio))–\(t.fim.map(hora) ?? "agora")"
    }
}

// MARK: - Peças reutilizadas nas telas de resumo

/// Linha "título ........ valor" com a confiança discreta (≈ / —) e detalhe ao tocar.
struct Campo: View {
    let titulo: String
    let medida: Medida
    let formatar: (Double) -> String

    init(_ titulo: String, _ medida: Medida, formatar: @escaping (Double) -> String) {
        self.titulo = titulo
        self.medida = medida
        self.formatar = formatar
    }

    var body: some View {
        LabeledContent(titulo) { MedidaTexto(medida: medida, formatar: formatar) }
    }
}

private struct Rotulo: View {
    let titulo: String
    let icone: String
    let valor: String

    init(_ titulo: String, _ icone: String, _ valor: String) {
        self.titulo = titulo
        self.icone = icone
        self.valor = valor
    }

    var body: some View {
        LabeledContent {
            Text(valor).monospacedDigit()
        } label: {
            Label(titulo, systemImage: icone)
        }
    }
}

// MARK: - Financeiro

private struct FinanceiroView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section("Faturamento") {
                Campo("Confirmado", r.faturamentoConfirmado) { Formato.reais($0) }
                Campo("Estimado (fora do total)", r.faturamentoEstimado) { Formato.reais($0) }
                Campo("Média por corrida confirmada", r.mediaPorCorrida) { Formato.reais($0) }
            }
            Section("Custos") {
                Campo("Abastecimentos", r.combustivel) { Formato.reais($0) }
                Campo("Outros custos", r.outrosCustos) { Formato.reais($0) }
                Campo("Custo estimado (custo/km × km)", r.custoEstimadoPorKm) { Formato.reais($0) }
                Campo("Combustível por km", r.combustivelPorKm) { Formato.reais($0) }
            }
            Section {
                Campo("Após custos registrados", r.resultado) { Formato.reais($0) }
                Campo("Após custo/km dos Ajustes", r.resultadoEstimado) { Formato.reais($0) }
            } header: {
                Text("Resultado")
            } footer: {
                Text("Abastecimento é o que você colocou no tanque, não o que gastou neste turno; por isso o resultado aparece como estimado. Em vários turnos a média fica precisa.")
            }
            Section("Por tempo e distância") {
                Campo("R$/hora", r.porHora) { Formato.reais($0) }
                Campo("R$/hora ativo (sem pausas)", r.porHoraAtivo) { Formato.reais($0) }
                Campo("R$/km", r.porKm) { Formato.reais($0) }
            }
        }
        .navigationTitle("Financeiro")
    }
}

// MARK: - Distância

private struct DistanciaView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                Campo("Total", r.km) { Formato.km($0) }
                ForEach([EstadoMotorista.emCorrida, .aCaminho, .aguardando, .pausado, .semLeitura], id: \.self) { e in
                    if let km = r.kmPorEstado[e], km >= 0.05 {
                        LabeledContent(e.nome, value: Formato.km(km))
                    }
                }
                if r.tempoSemSinalGPS >= 60 {
                    LabeledContent("Sem sinal (não somado)", value: Duracao.curta(r.tempoSemSinalGPS))
                }
            } footer: {
                Text(r.temGPS
                     ? "Distância do GPS filtrado: tremidas parado, saltos impossíveis e pontos imprecisos ficam de fora; trechos sem sinal não são ligados em linha reta."
                     : "Sem GPS neste turno.")
            }
        }
        .navigationTitle("Distância")
    }
}

// MARK: - Tempo

private struct TempoView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                LabeledContent("Duração do turno", value: Duracao.curta(r.duracao.valor ?? 0))
                Campo("Ativo (sem pausas)", r.tempoAtivo) { Duracao.curta($0) }
                ForEach(EstadoMotorista.allCases, id: \.self) { e in
                    if let s = r.tempoPorEstado[e], s >= 60 {
                        LabeledContent(e.nome) {
                            Text(Duracao.curta(s) + (r.percentual(e).map { String(format: "  %.0f%%", $0 * 100) } ?? ""))
                                .monospacedDigit()
                        }
                    }
                }
                Campo("Parado (GPS)", r.tempoParado) { Duracao.curta($0) }
            } footer: {
                Text("\"Sem leitura\" = a leitura da tela estava desligada: não dá pra saber o que aconteceu nesse tempo.")
            }
        }
        .navigationTitle("Tempo")
    }
}

// MARK: - Corridas

private struct CorridasView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            if r.corridas.isEmpty {
                Text("Nenhuma corrida detectada neste turno.").foregroundStyle(.secondary)
            }
            ForEach(r.corridas.reversed()) { c in
                NavigationLink { CorridaDetalheView(c: c) } label: { linha(c) }
            }
        }
        .navigationTitle("Corridas")
    }

    private func linha(_ c: CorridaAnalisada) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((c.aceiteEm ?? c.aBordoEm ?? c.encerradaEm).map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .font(.subheadline.bold())
                Text(([c.kmGPS.valor.map(Formato.km), c.duracao.valor.map(Duracao.curta)] as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MedidaTexto(medida: c.valor) { Formato.reais($0) }
            Etiqueta(texto: c.confianca?.nome ?? "ABERTA", cor: c.confianca?.cor ?? .blue)
        }
    }
}

private struct CorridaDetalheView: View {
    let c: CorridaAnalisada

    var body: some View {
        List {
            Section {
                LabeledContent("Estado", value: c.estado?.nome ?? "—")
                LabeledContent("Confiança") { Etiqueta(texto: c.confianca?.nome ?? "ABERTA", cor: c.confianca?.cor ?? .blue) }
                if c.motivo != .nenhum {
                    Text(c.motivo.texto(extra: c.falta)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Valor") {
                LabeledContent("Ofertado", value: c.valorOfertaCent.map { Formato.reais(Double($0) / 100) } ?? "—")
                LabeledContent("Final (tela de fim)", value: c.valorFinalCent.map { Formato.reais(Double($0) / 100) } ?? "não visto")
                LabeledContent("Associação oferta ↔ aceite") { Etiqueta(texto: c.ligacao.nome, cor: c.ligacao.cor) }
                Campo("R$/km", c.porKm) { Formato.reais($0) }
                Campo("R$/hora", c.porHora) { Formato.reais($0) }
            }
            Section("Distância e tempo") {
                LabeledContent("Busca (oferta)", value: c.buscaM.map { Formato.km(Double($0) / 1000) } ?? "—")
                LabeledContent("Viagem (oferta)", value: c.viagemM.map { Formato.km(Double($0) / 1000) } ?? "—")
                Campo("Km a bordo (GPS)", c.kmGPS) { Formato.km($0) }
                Campo("Duração a bordo", c.duracao) { Duracao.curta($0) }
                if let n = c.nota { LabeledContent("Nota do passageiro", value: Formato.nota(n)) }
            }
            Section("Horários") {
                hora("Aceite", c.aceiteEm)
                hora("Passageiro a bordo", c.aBordoEm)
                hora("Fim (tela)", c.fimEm)
                hora("Encerrada", c.encerradaEm)
            }
            Section("Onde") {
                LabeledContent("Origem (região)", value: c.regiaoOrigem ?? "sem GPS no embarque")
                LabeledContent("Destino (região)", value: c.regiaoDestino ?? "sem tela de fim com GPS")
            }
        }
        .navigationTitle("Corrida #\(c.id)")
    }

    private func hora(_ t: String, _ d: Date?) -> some View {
        LabeledContent(t, value: d.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
    }
}

// MARK: - Ofertas

private struct OfertasView: View {
    let r: ResumoTurno

    var body: some View {
        List {
            Section {
                LabeledContent("Recebidas", value: "\(r.ofertas.count)")
                LabeledContent("Aceitas", value: "\(r.ofertas.filter { $0.resultado == .aceita }.count)")
                LabeledContent("Não aceitas (recusou ou expirou)", value: "\(r.ofertas.filter { $0.resultado == .naoAceita }.count)")
            } footer: {
                Text("A tela não mostra se a oferta foi recusada ou só expirou; as duas contam como \"não aceita\".")
            }
            Section {
                ForEach(r.ofertas.reversed()) { o in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.em.formatted(date: .omitted, time: .shortened)).font(.subheadline.bold())
                            Text(([Formato.km(o.km), o.porKm.map { Formato.reais($0) + "/km" }, o.nota.map { "⭐ " + Formato.nota($0) }] as [String?])
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formato.reais(Double(o.valorCent) / 100)).monospacedDigit()
                        resultado(o)
                    }
                }
            }
        }
        .navigationTitle("Ofertas")
    }

    @ViewBuilder
    private func resultado(_ o: OfertaAnalisada) -> some View {
        switch o.resultado {
        case .aceita:    Etiqueta(texto: "ACEITA", cor: o.associacao?.cor ?? .green)
        case .naoAceita: Etiqueta(texto: "NÃO", cor: .gray)
        case .emAberto:  Etiqueta(texto: "…", cor: .blue)
        }
    }
}

// MARK: - Custos

private struct CustosView: View {
    let r: ResumoTurno
    @State private var novo = false

    var body: some View {
        List {
            if r.custos.isEmpty {
                Text("Nenhum custo registrado neste turno.").foregroundStyle(.secondary)
            }
            ForEach(r.custos) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.resumo)
                    Text(([c.em.formatted(date: .omitted, time: .shortened), c.precoLitro.map { String(format: "R$ %.3f/L", $0).replacingOccurrences(of: ".", with: ",") }, c.posto, c.observacao] as [String?])
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { novo = true } label: { Label("Abastecimento", systemImage: "plus") }
        }
        .navigationTitle("Abastecimentos e custos")
        .sheet(isPresented: $novo) { NavigationStack { AbastecimentoView() } }
    }
}

// MARK: - Mapa

/// Trajeto colorido por estado (verde = em corrida, azul = indo buscar, cinza = sem corrida).
/// Trechos sem sinal não aparecem ligados. Pontos: embarques (verde) e fins de corrida (vermelho).
struct MapaTurnoView: UIViewRepresentable {
    let r: ResumoTurno

    func makeUIView(context: Context) -> MKMapView {
        let mapa = MKMapView()
        mapa.delegate = context.coordinator
        mapa.pointOfInterestFilter = .excludingAll
        return mapa
    }

    func updateUIView(_ mapa: MKMapView, context: Context) {
        mapa.removeOverlays(mapa.overlays)
        mapa.removeAnnotations(mapa.annotations)

        // Junta trechos seguidos do mesmo estado numa linha só
        var grupos: [(estado: EstadoMotorista, pontos: [CLLocationCoordinate2D])] = []
        for t in r.trajeto.trechos {
            let estado = r.segmentos.first { $0.inicio <= t.meio && t.meio < $0.fim }?.estado ?? .semLeitura
            let de = CLLocationCoordinate2D(latitude: t.de.coord.lat, longitude: t.de.coord.lon)
            let para = CLLocationCoordinate2D(latitude: t.para.coord.lat, longitude: t.para.coord.lon)
            if let u = grupos.last, u.estado == estado, let fim = u.pontos.last,
               fim.latitude == de.latitude, fim.longitude == de.longitude {
                grupos[grupos.count - 1].pontos.append(para)
            } else {
                grupos.append((estado, [de, para]))
            }
        }
        for g in grupos {
            let linha = MKPolyline(coordinates: g.pontos, count: g.pontos.count)
            linha.title = g.estado.rawValue
            mapa.addOverlay(linha)
        }

        for c in r.corridas {
            if let o = c.origem { mapa.addAnnotation(Marca(o, "Embarque #\(c.id)", .systemGreen)) }
            if let d = c.destino { mapa.addAnnotation(Marca(d, "Fim #\(c.id)", .systemRed)) }
        }

        if let primeiro = mapa.overlays.first {
            let area = mapa.overlays.dropFirst().reduce(primeiro.boundingMapRect) { $0.union($1.boundingMapRect) }
            mapa.setVisibleMapRect(area, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
        }
    }

    func makeCoordinator() -> Coordenador { Coordenador() }

    final class Marca: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let cor: UIColor
        init(_ c: Coordenada, _ titulo: String, _ cor: UIColor) {
            coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
            title = titulo
            self.cor = cor
        }
    }

    final class Coordenador: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            switch EstadoMotorista(rawValue: overlay.title.flatMap { $0 } ?? "") {
            case .emCorrida?: r.strokeColor = .systemGreen
            case .aCaminho?:  r.strokeColor = .systemBlue
            default:          r.strokeColor = .systemGray
            }
            r.lineWidth = 4
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let m = annotation as? Marca else { return nil }
            let v = MKMarkerAnnotationView(annotation: m, reuseIdentifier: nil)
            v.markerTintColor = m.cor
            return v
        }
    }
}
