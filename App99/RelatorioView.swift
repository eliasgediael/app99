import SwiftUI

/// Histórico por dia, guardado de vez no app. Recebe os totais da extensão pelo CanalDarwin
/// (a extensão é a dona dos números do dia; aqui o dia recebido substitui o guardado).
@MainActor
final class RelatorioStore: ObservableObject {
    @Published private(set) var dias: [Int: DiaRelatorio] = [:]

    private let chave = "relatorio"
    private let chaveZerar = "zerarPendente"   // dia a zerar que a extensão ainda não confirmou
    private var receptor: ReceptorDarwin?
    private var observadorInicio: ObservadorDarwin?

    init() {
        if let dados = UserDefaults.standard.data(forKey: chave),
           let lista = try? JSONDecoder().decode([DiaRelatorio].self, from: dados) {
            dias = Dictionary(uniqueKeysWithValues: lista.map { ($0.dia, $0) })
        }
        receptor = ReceptorDarwin(canal: DiaRelatorio.canal) { [weak self] campos in
            guard let dia = DiaRelatorio(campos: campos) else { return }
            Task { @MainActor in self?.receber(dia) }
        }
        // Se zerou com a leitura desligada, repete o pedido quando ela ligar
        observadorInicio = ObservadorDarwin(SinalExtensao.iniciou.nome.rawValue as String) { [weak self] in
            Task { @MainActor in self?.repetirZerarSePendente() }
        }
    }

    /// Apaga os números de hoje, aqui e na extensão.
    func zerarHoje() {
        let hoje = DiaRelatorio.numero()
        UserDefaults.standard.set(hoje, forKey: chaveZerar)
        guardar(DiaRelatorio(dia: hoje))
        SinalApp.zerarHoje.enviar()
    }

    private func repetirZerarSePendente() {
        guard UserDefaults.standard.integer(forKey: chaveZerar) == DiaRelatorio.numero() else { return }
        SinalApp.zerarHoje.enviar()
    }

    /// Pede os últimos dias pra extensão (se a leitura estiver ligada, ela responde).
    func pedir() {
        CanalDarwin.postar(DiaRelatorio.nomePedido)
    }

    private func receber(_ dia: DiaRelatorio) {
        let d = UserDefaults.standard
        if d.integer(forKey: chaveZerar) == dia.dia {
            // Esperando a extensão confirmar o zerar: ignora números antigos, aceita os zerados
            guard dia.corridas == 0, dia.ofertas == 0, dia.faturadoCent == 0 else { return }
            d.removeObject(forKey: chaveZerar)
        }
        guardar(dia)
    }

    private func guardar(_ dia: DiaRelatorio) {
        guard dias[dia.dia] != dia else { return }
        dias[dia.dia] = dia
        if let dados = try? JSONEncoder().encode(Array(dias.values)) {
            UserDefaults.standard.set(dados, forKey: chave)
        }
    }

    var hoje: DiaRelatorio { dias[DiaRelatorio.numero()] ?? DiaRelatorio(dia: DiaRelatorio.numero()) }

    /// Hoje e os 6 dias antes dele.
    var semana: DiaRelatorio {
        let hoje = DiaRelatorio.numero()
        var total = DiaRelatorio(dia: hoje)
        for d in dias.values where d.dia > hoje - 7 {
            total.faturadoCent += d.faturadoCent
            total.custoCent += d.custoCent
            total.corridas += d.corridas
            total.metros += d.metros
            total.ofertas += d.ofertas
            total.segundos += d.segundos
        }
        return total
    }

    var anteriores: [DiaRelatorio] {
        let hoje = DiaRelatorio.numero()
        return dias.values.filter { $0.dia < hoje && ($0.corridas > 0 || $0.ofertas > 0) }
            .sorted { $0.dia > $1.dia }
    }
}

// MARK: - Tela

/// HOJE — sex, 25/09
/// 💵 Faturado      R$ 186,40
/// 🔧 Custo moto    R$ 29,75
/// 💰 Lucro         R$ 156,65
/// 🛵 14 corridas · 85 km
/// 📊 R$ 2,19/km médio · ⏱️ R$ 31,30/h
/// ✅ Aceitou 14 de 41 ofertas
struct ResumoDiaView: View {
    let dia: DiaRelatorio

    var body: some View {
        LabeledContent("💵 Faturado", value: Formato.reais(dia.faturado))
        LabeledContent("🔧 Custo moto", value: Formato.reais(dia.custo))
        LabeledContent("💰 Lucro") {
            Text(Formato.reais(dia.lucro)).bold().foregroundStyle(dia.lucro >= 0 ? .green : .red)
        }
        Text("🛵 \(dia.corridas) corrida\(dia.corridas == 1 ? "" : "s") · \(Formato.km(dia.km))")
        Text(linhaMedias)
        Text("✅ Aceitou \(dia.corridas) de \(dia.ofertas) oferta\(dia.ofertas == 1 ? "" : "s")")
    }

    private var linhaMedias: String {
        let porKm = dia.porKm.map { "\(Formato.reais($0))/km médio" } ?? "— /km"
        let porHora = dia.lucroPorHora.map { "\(Formato.reais($0))/h" } ?? "— /h"
        return "📊 \(porKm) · ⏱️ \(porHora)"
    }
}

struct RelatorioSections: View {
    @ObservedObject var store: RelatorioStore
    @State private var confirmarZerar = false

    var body: some View {
        Section {
            ResumoDiaView(dia: store.hoje)
            Button("Zerar hoje", role: .destructive) { confirmarZerar = true }
                .confirmationDialog("Apagar os números de hoje?", isPresented: $confirmarZerar, titleVisibility: .visible) {
                    Button("Zerar hoje", role: .destructive) { store.zerarHoje() }
                }
        } header: {
            Text("Hoje — \(Datas.curta(store.hoje.data))")
        } footer: {
            Text("A corrida entra quando você finaliza a viagem na 99. ⏱️ = lucro por hora com a leitura ligada. Prints de teste não contam.")
        }

        if !store.anteriores.isEmpty {
            Section("Últimos 7 dias") {
                ResumoDiaView(dia: store.semana)
            }

            Section("Dias anteriores") {
                ForEach(store.anteriores, id: \.dia) { dia in
                    NavigationLink {
                        List { ResumoDiaView(dia: dia) }
                            .navigationTitle(Datas.curta(dia.data))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Datas.curta(dia.data)).font(.headline)
                            Text("\(dia.corridas) corridas · \(Formato.reais(dia.faturado)) · lucro \(Formato.reais(dia.lucro))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

enum Datas {
    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE, dd/MM"
        return f
    }()

    /// "sex, 25/09"
    static func curta(_ data: Date) -> String {
        formato.string(from: data).replacingOccurrences(of: ".", with: "")
    }
}
