import CoreLocation

/// Nome de bairro para as regiões (células de ~1 km). OPCIONAL e desligado até você ativar no Perfil.
/// Quando ativo, o centro APROXIMADO da célula (não o seu trajeto) é enviado ao serviço de mapas
/// da Apple para descobrir o nome. Desligado: nada sai do iPhone e a região aparece pelo código.
@MainActor
final class NomesRegioes: ObservableObject {
    static let shared = NomesRegioes()
    static let chaveAtivo = "identificarBairros"
    private static let chaveCache = "nomesRegioes"

    @Published private(set) var nomes: [String: String]
    private var fila: [String] = []
    private var buscando = false
    private let geocoder = CLGeocoder()

    var ativo: Bool { UserDefaults.standard.bool(forKey: Self.chaveAtivo) }

    init() {
        nomes = UserDefaults.standard.dictionary(forKey: Self.chaveCache) as? [String: String] ?? [:]
    }

    /// "Centro" (se ativo e já conhecido) ou "Região 6vfq3k".
    func rotulo(_ geohash: String) -> String {
        if ativo {
            if let n = nomes[geohash], !n.isEmpty { return n }
            if nomes[geohash] == nil { pedir(geohash) }
        }
        return "Região \(geohash)"
    }

    /// Apaga os nomes guardados (ao desligar a opção).
    func apagarNomes() {
        fila.removeAll()
        nomes = [:]
        UserDefaults.standard.removeObject(forKey: Self.chaveCache)
    }

    private func pedir(_ g: String) {
        guard !fila.contains(g) else { return }
        fila.append(g)
        // Fora da atualização da tela (pedido feito durante o desenho de uma view)
        Task { @MainActor in self.processar() }
    }

    /// Um pedido por vez, com intervalo (o serviço da Apple limita a quantidade por minuto).
    private func processar() {
        guard !buscando, ativo, let g = fila.first, let c = Geohash.centro(g) else {
            if !ativo { fila.removeAll() }
            return
        }
        buscando = true
        geocoder.reverseGeocodeLocation(CLLocation(latitude: c.lat, longitude: c.lon)) { lugares, erro in
            let nome = lugares?.first.flatMap { $0.subLocality ?? $0.locality }
            Task { @MainActor in
                self.fila.removeAll { $0 == g }
                // Erro de rede: tenta de novo numa próxima vez; sem nome: guarda vazio (não pergunta de novo)
                if erro == nil || nome != nil {
                    self.nomes[g] = nome ?? ""
                    UserDefaults.standard.set(self.nomes, forKey: Self.chaveCache)
                }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                self.buscando = false
                self.processar()
            }
        }
    }
}
