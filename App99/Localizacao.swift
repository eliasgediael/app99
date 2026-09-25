import CoreLocation

/// GPS do turno. Liga SÓ quando você inicia o turno e desliga quando encerra —
/// nada de localização fora disso. Enquanto liga, o iOS mostra a pílula azul no topo.
///
/// Efeito colateral bom: com a localização em segundo plano, o iOS mantém o app vivo,
/// então ele recebe os eventos da leitura na hora (e marca onde cada um aconteceu).
@MainActor
final class Localizacao: NSObject, ObservableObject {
    static let shared = Localizacao()

    enum Estado: Equatable {
        case desligado
        case semPermissao
        case procurando      // ligado, sem ponto bom ainda
        case ativo
        case semSinal        // > 2 min sem ponto válido

        var nome: String {
            switch self {
            case .desligado:    return "GPS desligado"
            case .semPermissao: return "Sem permissão de localização"
            case .procurando:   return "Procurando GPS"
            case .ativo:        return "GPS ativo"
            case .semSinal:     return "GPS sem sinal"
            }
        }
    }

    @Published private(set) var estado: Estado = .desligado
    @Published private(set) var precisaoM: Double?

    private let gerente = CLLocationManager()
    private var querLigado = false
    private var ligadoEm: Date?
    private var ultimoPontoBom: Date?
    private var semSinalRegistrado = false
    private var verificador: Timer?

    private let limiteSemSinal: TimeInterval = 120

    override init() {
        super.init()
        gerente.delegate = self
        gerente.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        gerente.distanceFilter = kCLDistanceFilterNone   // o TurnoStore decide o que guardar (10 m ou 15 s)
        gerente.activityType = .otherNavigation
        gerente.pausesLocationUpdatesAutomatically = false
    }

    /// Chamado ao iniciar (ou retomar, se o app reabriu com turno ativo).
    func ligar() {
        querLigado = true
        switch gerente.authorizationStatus {
        case .notDetermined:
            estado = .procurando
            gerente.requestWhenInUseAuthorization()   // liga de fato quando a resposta chegar
        case .denied, .restricted:
            estado = .semPermissao
        default:
            comecar()
        }
    }

    func desligar() {
        querLigado = false
        gerente.stopUpdatingLocation()
        gerente.allowsBackgroundLocationUpdates = false
        verificador?.invalidate()
        verificador = nil
        estado = .desligado
        precisaoM = nil
        TurnoStore.shared.salvarPontos()
    }

    private func comecar() {
        guard querLigado else { return }
        gerente.allowsBackgroundLocationUpdates = true      // precisa do modo "location" no Info.plist
        gerente.showsBackgroundLocationIndicator = true
        gerente.startUpdatingLocation()
        ligadoEm = Date()
        if estado != .ativo { estado = .procurando }
        verificador?.invalidate()
        verificador = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verificarSinal() }
        }
    }

    private func autorizacaoMudou() {
        switch gerente.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: if querLigado { comecar() }
        case .denied, .restricted:                   if querLigado { estado = .semPermissao }
        default: break
        }
    }

    private func recebeu(_ pontos: [PontoGPS]) {
        guard querLigado else { return }
        for p in pontos {
            precisaoM = p.precisaoM
            guard p.precisaoM <= Trajeto.precisaoMaxima else { continue }
            ultimoPontoBom = p.em
            TurnoStore.shared.adicionarPonto(p)
        }
        if ultimoPontoBom != nil, let u = ultimoPontoBom, Date().timeIntervalSince(u) < limiteSemSinal {
            if semSinalRegistrado {
                semSinalRegistrado = false
                TurnoStore.shared.registrarGPS(.gpsRetomado, texto: "GPS voltou")
            }
            estado = .ativo
        }
    }

    /// Sem ponto bom há mais de 2 min: registra UMA vez (o trajeto não liga os pontos desse buraco).
    private func verificarSinal() {
        guard querLigado, estado != .semPermissao else { return }
        let referencia = ultimoPontoBom ?? ligadoEm ?? Date()
        guard Date().timeIntervalSince(referencia) > limiteSemSinal else { return }
        estado = .semSinal
        if !semSinalRegistrado {
            semSinalRegistrado = true
            TurnoStore.shared.registrarGPS(.gpsSemSinal, texto: "GPS sem sinal há mais de 2 min")
        }
    }
}

extension Localizacao: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.autorizacaoMudou() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let pontos = locations.compactMap { l -> PontoGPS? in
            guard l.horizontalAccuracy >= 0 else { return nil }   // < 0 = inválido
            return PontoGPS(em: l.timestamp,
                            coord: Coordenada(lat: l.coordinate.latitude, lon: l.coordinate.longitude),
                            precisaoM: l.horizontalAccuracy,
                            velocidadeMS: l.speed >= 0 ? l.speed : nil)
        }
        Task { @MainActor in self.recebeu(pontos) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let negado = (error as? CLError)?.code == .denied
        Task { @MainActor in if negado { self.estado = .semPermissao } }
    }
}
