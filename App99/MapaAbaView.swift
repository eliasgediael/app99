import SwiftUI

/// Aba Mapa: o mapa do turno (o mesmo do resumo). Por padrão o turno ativo, senão o último.
/// Filtros e linha do tempo sincronizada chegam na Fase 5.
struct MapaAbaView: View {
    @ObservedObject var turnos = TurnoStore.shared
    @State private var escolhido: UUID?

    private var lista: [Turno] { turnos.turnos.sorted { $0.inicio > $1.inicio } }

    private var turno: Turno? {
        if let id = escolhido, let t = turnos.turnos.first(where: { $0.id == id }) { return t }
        return turnos.atual ?? turnos.ultimoEncerrado
    }

    var body: some View {
        Group {
            if let t = turno {
                let r = turnos.resumo(t)
                if r.temGPS {
                    MapaTurnoView(r: r)
                } else {
                    semMapa("Sem trajeto de GPS neste turno.")
                }
            } else {
                semMapa("Nenhum turno ainda. O trajeto aparece aqui quando você rodar com o GPS ligado.")
            }
        }
        .navigationTitle(turno.map { ResumoTurnoView.titulo($0) } ?? "Mapa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !lista.isEmpty {
                    Menu {
                        Picker("Turno", selection: Binding(get: { turno?.id }, set: { escolhido = $0 })) {
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
    }

    private func semMapa(_ texto: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
            Text(texto).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
