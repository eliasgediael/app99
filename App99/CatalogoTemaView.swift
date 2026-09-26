import SwiftUI

/// Catálogo do design system (Mais → Visual do Apex). Só pra conferir tokens e componentes.
/// EXEMPLO: todos os números aqui são ilustrativos, não vêm do seu histórico e não são gravados.
struct CatalogoTemaView: View {
    @State private var filtro = "Todas"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                Aviso(nivel: .info, texto: "Exemplo visual. Nenhum número desta tela é seu nem é salvo.")

                // Hierarquia: 1 número forte, secundárias, estado, ação
                VStack(alignment: .leading, spacing: Espaco.l) {
                    PontoEstado(texto: "Turno ativo · 02:14", cor: Tema.positivo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("R$ 96,40")
                            .font(Tipo.destaque)
                            .foregroundStyle(Tema.positivo)
                            .monospacedDigit()
                        Text("faturamento confirmado")
                            .font(Tipo.apoio)
                            .foregroundStyle(Tema.textoSecundario)
                    }
                    HStack(spacing: Espaco.l) {
                        MetricaCompacta(valor: "R$ 43,20", rotulo: "por hora")
                        MetricaCompacta(valor: "58,6 km", rotulo: "rodados")
                        MetricaCompacta(valor: "R$ 1,64", rotulo: "por km", confianca: .estimado)
                    }
                    PontoEstado(texto: "Aguardando corrida", cor: EstadoMotorista.aguardando.cor)
                    Button("Iniciar turno") {}.buttonStyle(BotaoPrimario())
                    Button("Pausar") {}.buttonStyle(BotaoSecundario())
                }

                VStack(alignment: .leading, spacing: Espaco.m) {
                    CabecalhoSecao("Cores")
                    amostra("Fundo", Tema.fundo)
                    amostra("Superfície", Tema.superficie)
                    amostra("Primária · azul-petróleo", Tema.primaria)
                    amostra("Positivo · menta (só confirmado)", Tema.positivo)
                    amostra("Atenção · estimado", Tema.atencao)
                    amostra("Erro", Tema.erro)
                    amostra("Neutro · indeterminado", Tema.neutro)
                }

                VStack(alignment: .leading, spacing: Espaco.m) {
                    CabecalhoSecao("Estados")
                    ForEach(EstadoMotorista.allCases, id: \.self) { e in
                        PontoEstado(texto: e.nome, cor: e.cor)
                    }
                    PontoEstado(texto: "Oferta detectada · não é faturamento", cor: Tema.neutro)
                }

                VStack(alignment: .leading, spacing: 0) {
                    CabecalhoSecao("Métricas em linha") { Text("Ver tudo") }
                    LinhaMetrica("Confirmado", "R$ 96,40")
                    Divisoria()
                    LinhaMetrica("Estimado (fora do total)", texto: Text("≈ R$ 6,80").foregroundColor(Tema.atencao))
                    Divisoria()
                    LinhaMetrica("Sem dado", "—")
                }

                VStack(alignment: .leading, spacing: Espaco.m) {
                    CabecalhoSecao("Filtros")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Espaco.s) {
                            ForEach(["Todas", "Viagens", "Embarques", "Sem corrida", "Ofertas"], id: \.self) { f in
                                ChipFiltro(titulo: f, ativo: filtro == f) { filtro = f }
                            }
                        }
                    }
                }

                BlocoGrafico("Bloco denso", subtitulo: "Atividade e Análises usam este") {
                    Text("Gráficos e grupos entram aqui.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Tema.textoSecundario)
                }

                VStack(alignment: .leading, spacing: Espaco.m) {
                    CabecalhoSecao("Avisos")
                    Aviso(nivel: .atencao, texto: "GPS sem sinal: esse trecho não entra nos km.")
                    Aviso(nivel: .erro, texto: "Sem permissão de localização.")
                    Carregando(texto: "Lendo o turno…")
                }

                EstadoVazio(icone: "car", titulo: "Nenhuma viagem ainda",
                            texto: "As corridas do turno aparecem aqui.", acaoTitulo: "Iniciar turno") {}
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.vertical, Espaco.l)
        }
        .background(Tema.fundo.ignoresSafeArea())
        .navigationTitle("Visual do Apex")
    }

    private func amostra(_ nome: String, _ cor: Color) -> some View {
        HStack(spacing: Espaco.m) {
            RoundedRectangle(cornerRadius: 6).fill(cor)
                .frame(width: 36, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tema.linha))
            Text(nome).font(Tipo.apoio).foregroundStyle(Tema.texto)
        }
    }
}
