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

    private var lista: [Turno] { turnos.turnosComRegistro.sorted { $0.inicio > $1.inicio } }

    private var turno: Turno? {
        if let id = escolhido, let t = turnos.turnos.first(where: { $0.id == id }) { return t }
        return turnos.atual ?? lista.first
    }

    var body: some View {
        Group {
            if let t = turno {
                let r = turnos.resumo(t)
                if r.temGPS {
                    mapa(r)
                } else {
                    EstadoVazio(icone: "location.slash", titulo: "Sem trajeto neste turno")
                        .frame(maxHeight: .infinity)
                }
            } else {
                EstadoVazio(icone: "map", titulo: "Nenhum turno registrado")
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
            if let t = turno {
                let r = turnos.resumo(t)
                if let c = r.corridas.first(where: { $0.id == a.id }) {
                    NavigationStack {
                        CorridaDetalheView(c: c, r: r)
                            .toolbar { Button("OK") { aberta = nil } }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func mapa(_ r: ResumoTurno) -> some View {
        MapaTurnoView(r: r, filtro: filtro, intervalo: intervalo, corridaFoco: corridaFoco,
                      enquadrar: enquadrar) { id in aberta = CorridaAberta(id: id) }
            .overlay(alignment: .top) {
                VStack(spacing: Espaco.s) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FiltroMapa.allCases) { f in
                                Button { filtro = f } label: {
                                    Text(f.nome)
                                        .font(Tipo.legenda.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .background(filtro == f ? AnyShapeStyle(Tema.texto) : AnyShapeStyle(.regularMaterial), in: Capsule())
                                        .foregroundStyle(filtro == f ? Tema.fundo : Tema.texto)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Espaco.margem)
                    }
                    if let texto = textoFoco(r) {
                        Button(action: limparFoco) {
                            HStack(spacing: 6) {
                                Text(texto)
                                Image(systemName: "xmark")
                            }
                            .font(Tipo.legenda.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(Tema.primaria, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Espaco.s)
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    legenda
                    Spacer()
                    Button { enquadrar += 1 } label: {
                        Image(systemName: "scope")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                            .foregroundStyle(Tema.primaria)
                    }
                    .accessibilityLabel("Enquadrar")
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, Espaco.m)
            }
    }

    private var legenda: some View {
        HStack(spacing: Espaco.m) {
            switch filtro {
            case .ofertas:       item("Oferta", Tema.neutro)
            case .abastecimento: item("Abastecimento", Tema.abastecimento)
            case .corridas:      item("Em corrida", Tema.mapaEmCorrida)
            case .busca:         item("Busca", Tema.mapaIndoBuscar)
            case .semCorrida:    item("Sem corrida", Tema.mapaSemCorrida)
            case .todas:
                item("Corrida", Tema.mapaEmCorrida)
                item("Busca", Tema.mapaIndoBuscar)
                item("Sem corrida", Tema.mapaSemCorrida)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(.regularMaterial, in: Capsule())
    }

    private func item(_ nome: String, _ cor: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(cor).frame(width: 12, height: 4)
            Text(nome).font(.caption2.weight(.semibold)).foregroundStyle(Tema.texto)
        }
    }

    private func textoFoco(_ r: ResumoTurno) -> String? {
        if let id = corridaFoco, let c = r.corridas.first(where: { $0.id == id }) {
            return "Corrida · \(c.terminoVisto.map(Datas.hora) ?? "")"
        }
        if let i = intervalo {
            return "\(Datas.hora(i.start))–\(Datas.hora(i.end))"
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

// MARK: - Mapa

/// MKMapView: o Map do SwiftUI com linhas e marcadores só existe a partir do iOS 17.
/// Enquadra só quando muda o que se está vendo (turno, filtro, foco, botão): ponto novo do GPS
/// redesenha a linha sem mexer no zoom do usuário.
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
                guard c.feita else { continue }
                if let o = c.origem, naJanela(c.aBordoEm) {
                    mapa.addAnnotation(Marca(o, .embarque, c.valorTexto, "Embarque · " + (c.aBordoEm.map(Datas.hora) ?? ""), corrida: c.id))
                }
                if let d = c.destino, naJanela(c.fimEm) {
                    mapa.addAnnotation(Marca(d, .desembarque, c.valorTexto, "Desembarque · " + (c.fimEm.map(Datas.hora) ?? ""), corrida: c.id))
                }
            }
        }
        if filtro == .ofertas {
            for o in r.ofertas where naJanela(o.em) {
                guard let l = o.local else { continue }
                mapa.addAnnotation(Marca(l, .oferta, Formato.reais(Double(o.valorCent) / 100), "Oferta · " + Datas.hora(o.em)))
            }
        }
        if filtro == .todas || filtro == .abastecimento {
            for c in r.custos where c.tipo == .combustivel && naJanela(c.em) {
                guard let l = c.local else { continue }
                mapa.addAnnotation(Marca(l, .abastecimento, Formato.reais(c.valor), "Abastecimento · " + Datas.hora(c.em)))
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
                v.markerTintColor = UIColor(Tema.abastecimento)
                v.glyphImage = UIImage(systemName: "fuelpump.fill")
            }
            if m.corrida != nil {
                v.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            }
            return v
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let m = view.annotation as? Marca, let id = m.corrida else { return }
            aoTocarCorrida?(id)
        }
    }
}
