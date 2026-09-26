import SwiftUI
import MapKit

// MARK: - Filtros

enum FiltroMapa: String, CaseIterable, Identifiable {
    case todas, corridas, busca, semCorrida, ofertas, abastecimento
    var id: Self { self }

    var nome: String {
        switch self {
        case .todas:         return "Todas"
        case .corridas:      return "Corridas"
        case .busca:         return "Busca"
        case .semCorrida:    return "Sem corrida"
        case .ofertas:       return "Ofertas"
        case .abastecimento: return "Abastecimento"
        }
    }

    /// Estado do trajeto que este filtro destaca (nil = todos coloridos, ou só pontos).
    var estadoDestacado: EstadoMotorista? {
        switch self {
        case .corridas:   return .emCorrida
        case .busca:      return .aCaminho
        case .semCorrida: return .aguardando
        default:          return nil
        }
    }
}

// MARK: - Aba Mapa

/// Mapa do turno como ferramenta de análise: filtros, legenda, toque no embarque/desembarque abre a corrida.
/// Chega focado quando outra tela manda (corrida → mapa, hora da Atividade → mapa).
struct MapaAbaView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @ObservedObject var linha = LinhaDoTempoStore.shared
    @ObservedObject var nav = Navegacao.shared

    @State private var escolhido: UUID?
    @State private var filtro = FiltroMapa.todas
    @State private var intervalo: DateInterval?
    @State private var corridaFoco: Int?
    @State private var enquadrar = 0
    @State private var aberta: CorridaAberta?

    struct CorridaAberta: Identifiable { let id: Int }

    private var lista: [Turno] { turnos.turnos.sorted { $0.inicio > $1.inicio } }

    private var turno: Turno? {
        if let id = escolhido, let t = turnos.turnos.first(where: { $0.id == id }) { return t }
        return turnos.atual ?? turnos.ultimoEncerrado
    }

    var body: some View {
        Group {
            if let t = turno {
                conteudo(turnos.resumo(t))
            } else {
                EstadoVazio(icone: "map", titulo: "Nenhum turno ainda",
                            texto: "O trajeto aparece aqui quando você rodar um turno com o GPS ligado.")
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle(turno.map { ResumoTurnoView.titulo($0) } ?? "Mapa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !lista.isEmpty {
                    Menu {
                        Picker("Turno", selection: Binding(get: { turno?.id }, set: { novo in
                            escolhido = novo
                            limparFoco()
                        })) {
                            ForEach(lista) { t in
                                Text(ResumoTurnoView.titulo(t)).tag(Optional(t.id))
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Escolher turno")
                }
            }
        }
        .onAppear(perform: aplicarFoco)
        .onChange(of: nav.focoMapa) { _ in aplicarFoco() }
        .sheet(item: $aberta) { a in
            if let t = turno, let c = turnos.resumo(t).corridas.first(where: { $0.id == a.id }) {
                NavigationStack {
                    CorridaDetalheView(c: c, r: turnos.resumo(t))
                        .toolbar { Button("OK") { aberta = nil } }
                }
            }
        }
    }

    @ViewBuilder
    private func conteudo(_ r: ResumoTurno) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espaco.s) {
                    ForEach(FiltroMapa.allCases) { f in
                        ChipFiltro(titulo: f.nome, ativo: filtro == f) { filtro = f }
                    }
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.vertical, Espaco.s)
            }

            if let texto = textoFoco(r) {
                HStack {
                    Image(systemName: "scope").foregroundStyle(Tema.primaria)
                    Text(texto).font(Tipo.apoio).foregroundStyle(Tema.texto)
                    Spacer()
                    Button("Mostrar tudo") { limparFoco() }
                        .font(Tipo.apoio.weight(.semibold))
                        .foregroundStyle(Tema.primaria)
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.vertical, Espaco.s)
                .background(Tema.superficie)
            }

            if r.temGPS {
                ZStack(alignment: .bottomTrailing) {
                    MapaTurnoView(r: r, filtro: filtro, intervalo: intervalo, corridaFoco: corridaFoco,
                                  enquadrar: enquadrar) { id in aberta = CorridaAberta(id: id) }
                    Button { enquadrar += 1 } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Tema.superficie, in: Circle())
                            .foregroundStyle(Tema.primaria)
                    }
                    .accessibilityLabel("Enquadrar o trajeto")
                    .padding(Espaco.m)
                }
                legenda(r)
            } else {
                EstadoVazio(icone: "location.slash", titulo: "Sem trajeto neste turno",
                            texto: "O GPS não registrou pontos neste turno (sem permissão ou desligado). Os números da tela continuam valendo; só o mapa e os km ficam de fora.")
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func legenda(_ r: ResumoTurno) -> some View {
        VStack(alignment: .leading, spacing: Espaco.xs) {
            HStack(spacing: Espaco.m) {
                switch filtro {
                case .ofertas:
                    item("Oferta recebida (onde você estava)", Tema.neutro)
                case .abastecimento:
                    item("Abastecimento", Color.purple)
                default:
                    if filtro == .todas || filtro == .corridas { item("Em corrida", Tema.mapaEmCorrida) }
                    if filtro == .todas || filtro == .busca { item("Indo buscar", Tema.mapaIndoBuscar) }
                    if filtro == .todas || filtro == .semCorrida { item("Sem corrida", Tema.mapaSemCorrida) }
                }
            }
            Text(resumoFiltro(r))
                .font(Tipo.legenda)
                .monospacedDigit()
                .foregroundStyle(Tema.textoSecundario)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Espaco.margem)
        .padding(.vertical, Espaco.m)
        .background(Tema.superficie)
    }

    private func item(_ nome: String, _ cor: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(cor).frame(width: 14, height: 5)
            Text(nome).font(Tipo.legenda).foregroundStyle(Tema.textoSecundario)
        }
    }

    private func resumoFiltro(_ r: ResumoTurno) -> String {
        switch filtro {
        case .todas:
            return "\(PainelTurno.corridas(r.corridasFeitas)) · " + (r.km.valor.map(Formato.km) ?? "— km")
                + " · toque num embarque ou desembarque e depois no (i) pra abrir a corrida"
        case .corridas, .busca, .semCorrida:
            let e = filtro.estadoDestacado ?? .emCorrida
            let km = r.kmPorEstado[e] ?? 0
            let tempo = r.tempoPorEstado[e] ?? 0
            return "\(e.nome): \(Formato.km(km)) · \(Duracao.curta(tempo))"
        case .ofertas:
            let comLocal = r.ofertas.filter { $0.local != nil }.count
            return "\(comLocal) de \(r.ofertas.count) ofertas com local. Oferta não é faturamento."
        case .abastecimento:
            let comLocal = r.custos.filter { $0.tipo == .combustivel && $0.local != nil }.count
            let total = r.custos.filter { $0.tipo == .combustivel }.count
            return total == 0 ? "Nenhum abastecimento neste turno." : "\(comLocal) de \(total) abastecimentos com local."
        }
    }

    private func textoFoco(_ r: ResumoTurno) -> String? {
        if let id = corridaFoco, let c = r.corridas.first(where: { $0.id == id }) {
            return "Corrida das \(c.inicioVisto.map(PainelTurno.hora) ?? "—")"
        }
        if let i = intervalo {
            return "Mostrando \(PainelTurno.hora(i.start))–\(PainelTurno.hora(i.end))"
        }
        return nil
    }

    private func aplicarFoco() {
        guard let f = nav.focoMapa else { return }
        aberta = nil
        escolhido = f.turno
        intervalo = f.intervalo
        corridaFoco = f.corrida
        filtro = .todas
        enquadrar += 1
        nav.focoMapa = nil
    }

    private func limparFoco() {
        intervalo = nil
        corridaFoco = nil
        enquadrar += 1
    }
}

// MARK: - Mapa (MKMapView: o Map do SwiftUI com overlays só existe no iOS 17)

/// Trajeto colorido por estado, embarques (●) e desembarques (⚑), ofertas e abastecimentos.
/// Enquadra só na primeira vez e quando muda o que se está vendo (turno, filtro, foco, botão):
/// ponto novo do GPS redesenha a linha mas não mexe no zoom que você deu.
struct MapaTurnoView: UIViewRepresentable {
    let r: ResumoTurno
    var filtro: FiltroMapa = .todas
    var intervalo: DateInterval? = nil
    var corridaFoco: Int? = nil
    var interativo = true
    var enquadrar = 0
    var aoTocarCorrida: ((Int) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapa = MKMapView()
        mapa.delegate = context.coordinator
        mapa.pointOfInterestFilter = .excludingAll
        mapa.isUserInteractionEnabled = interativo
        mapa.showsCompass = interativo
        return mapa
    }

    func updateUIView(_ mapa: MKMapView, context: Context) {
        let co = context.coordinator
        co.aoTocarCorrida = aoTocarCorrida
        let dados = "\(r.turno.id)|\(r.trajeto.trechos.count)|\(r.corridas.count)|\(r.ofertas.count)|\(r.custos.count)|\(r.segmentos.count)"
        let visao = "\(r.turno.id)|\(filtro.rawValue)|\(intervalo?.start.timeIntervalSince1970 ?? 0)|\(intervalo?.end.timeIntervalSince1970 ?? 0)|\(corridaFoco ?? 0)|\(enquadrar)"
        guard dados != co.dados || visao != co.visao else { return }
        desenhar(mapa)
        if visao != co.visao { enquadrarVisao(mapa, animado: co.visao != nil) }
        co.dados = dados
        co.visao = visao
    }

    /// Janela de tempo em foco: a corrida (do aceite ao fim) ou o intervalo pedido.
    private var janela: DateInterval? {
        if let id = corridaFoco, let c = r.corridas.first(where: { $0.id == id }),
           let de = c.aceiteEm ?? c.aBordoEm {
            let ate = max(de, c.terminoVisto ?? Date())
            return DateInterval(start: de, end: ate)
        }
        return intervalo
    }

    private func desenhar(_ mapa: MKMapView) {
        mapa.removeOverlays(mapa.overlays)
        mapa.removeAnnotations(mapa.annotations)
        let janela = janela
        let destaque = filtro.estadoDestacado

        // Junta trechos seguidos do mesmo estilo numa linha só
        var grupos: [(estilo: String, pontos: [CLLocationCoordinate2D])] = []
        for t in r.trajeto.trechos {
            let dentro = janela.map { $0.contains(t.meio) } ?? true
            let estado = r.segmentos.first { $0.inicio <= t.meio && t.meio < $0.fim }?.estado ?? .semLeitura
            let colorido: Bool
            switch filtro {
            case .todas:                     colorido = dentro
            case .corridas, .busca, .semCorrida: colorido = dentro && estado == destaque
            case .ofertas, .abastecimento:   colorido = false
            }
            let estilo = colorido ? estado.rawValue : "fundo"
            let de = CLLocationCoordinate2D(latitude: t.de.coord.lat, longitude: t.de.coord.lon)
            let para = CLLocationCoordinate2D(latitude: t.para.coord.lat, longitude: t.para.coord.lon)
            if let u = grupos.last, u.estilo == estilo, let fim = u.pontos.last,
               fim.latitude == de.latitude, fim.longitude == de.longitude {
                grupos[grupos.count - 1].pontos.append(para)
            } else {
                grupos.append((estilo, [de, para]))
            }
        }
        // Fundo primeiro (fica por baixo)
        for g in grupos.sorted(by: { ($0.estilo == "fundo" ? 0 : 1) < ($1.estilo == "fundo" ? 0 : 1) }) {
            let linha = MKPolyline(coordinates: g.pontos, count: g.pontos.count)
            linha.title = g.estilo
            mapa.addOverlay(linha)
        }

        func naJanela(_ d: Date?) -> Bool {
            guard let janela else { return true }
            return d.map { janela.contains($0) } ?? false
        }

        if filtro == .todas || filtro == .corridas {
            for c in r.corridas where !c.cancelada && (corridaFoco == nil || c.id == corridaFoco) {
                let valor = c.valorTexto
                if let o = c.origem, naJanela(c.aBordoEm) {
                    mapa.addAnnotation(Marca(o, .embarque, "Embarque · \(c.aBordoEm.map(PainelTurno.hora) ?? "")", valor, corrida: c.id))
                }
                if let d = c.destino, naJanela(c.fimEm) {
                    mapa.addAnnotation(Marca(d, .desembarque, "Desembarque · \(c.fimEm.map(PainelTurno.hora) ?? "")", valor, corrida: c.id))
                }
            }
        }
        if filtro == .ofertas {
            for o in r.ofertas where naJanela(o.em) {
                guard let l = o.local else { continue }
                mapa.addAnnotation(Marca(l, .oferta, "Oferta · \(PainelTurno.hora(o.em))",
                                         "\(Formato.reais(Double(o.valorCent) / 100)) · não é faturamento"))
            }
        }
        if filtro == .todas || filtro == .abastecimento {
            for c in r.custos where c.tipo == .combustivel && naJanela(c.em) {
                guard let l = c.local else { continue }
                mapa.addAnnotation(Marca(l, .abastecimento, "Abastecimento · \(PainelTurno.hora(c.em))", c.resumo))
            }
        }
    }

    private func enquadrarVisao(_ mapa: MKMapView, animado: Bool) {
        let destacadas = mapa.overlays.filter { ($0.title ?? nil) != "fundo" }
        var area: MKMapRect?
        for o in (destacadas.isEmpty ? mapa.overlays : destacadas) {
            area = area.map { $0.union(o.boundingMapRect) } ?? o.boundingMapRect
        }
        for a in mapa.annotations {
            let p = MKMapPoint(a.coordinate)
            let r = MKMapRect(x: p.x - 300, y: p.y - 300, width: 600, height: 600)
            area = area.map { $0.union(r) } ?? r
        }
        guard let area else { return }
        mapa.setVisibleMapRect(area, edgePadding: UIEdgeInsets(top: 48, left: 40, bottom: 48, right: 40), animated: animado)
    }

    func makeCoordinator() -> Coordenador { Coordenador() }

    enum TipoMarca { case embarque, desembarque, oferta, abastecimento }

    final class Marca: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let subtitle: String?
        let tipo: TipoMarca
        let corrida: Int?
        init(_ c: Coordenada, _ tipo: TipoMarca, _ titulo: String, _ subtitulo: String?, corrida: Int? = nil) {
            coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
            title = titulo
            subtitle = subtitulo
            self.tipo = tipo
            self.corrida = corrida
        }
    }

    final class Coordenador: NSObject, MKMapViewDelegate {
        var dados: String?
        var visao: String?
        var aoTocarCorrida: ((Int) -> Void)?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.lineCap = .round
            r.lineJoin = .round
            let estilo = overlay.title.flatMap { $0 } ?? ""
            switch EstadoMotorista(rawValue: estilo) {
            case .emCorrida?:  r.strokeColor = UIColor(Tema.mapaEmCorrida); r.lineWidth = 5
            case .aCaminho?:   r.strokeColor = UIColor(Tema.mapaIndoBuscar); r.lineWidth = 5
            case .aguardando?: r.strokeColor = UIColor(Tema.mapaSemCorrida); r.lineWidth = 4
            case .pausado?:    r.strokeColor = UIColor(Tema.atencao); r.lineWidth = 4
            case .semLeitura?: r.strokeColor = UIColor(Tema.textoTerciario); r.lineWidth = 3
            case nil:          r.strokeColor = UIColor(Tema.neutro).withAlphaComponent(0.35); r.lineWidth = 3
            }
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let m = annotation as? Marca else { return nil }
            let v = MKMarkerAnnotationView(annotation: m, reuseIdentifier: nil)
            v.canShowCallout = true
            switch m.tipo {
            case .embarque:
                v.markerTintColor = UIColor(Tema.positivo)
                v.glyphImage = UIImage(systemName: "person.fill")
            case .desembarque:
                v.markerTintColor = UIColor(Tema.primaria)
                v.glyphImage = UIImage(systemName: "flag.fill")
            case .oferta:
                v.markerTintColor = UIColor(Tema.neutro)
                v.glyphImage = UIImage(systemName: "tag.fill")
                v.displayPriority = .defaultLow
            case .abastecimento:
                v.markerTintColor = .systemPurple
                v.glyphImage = UIImage(systemName: "fuelpump.fill")
            }
            if m.corrida != nil {
                v.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            }
            return v
        }

        /// Toque no (i) do balão de um embarque/desembarque abre a corrida.
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let m = view.annotation as? Marca, let id = m.corrida else { return }
            aoTocarCorrida?(id)
        }
    }
}
