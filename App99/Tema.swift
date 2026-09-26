import SwiftUI
import UIKit

// MARK: - Apex · Design system
//
// Tokens (cor, tipo, espaço, forma) e componentes base. Toda tela nova usa daqui.
// Regras da identidade:
// - Menta só pra coisa boa e real: faturamento CONFIRMADO, operação funcionando, meta atingida.
// - Oferta nunca em menta (oferta não é dinheiro).
// - Estimado = âmbar discreto ("≈"); indeterminado = neutro ("—").
// - Hierarquia por tipografia, contraste e espaço — não por caixas e bordas.

// MARK: Cores

enum Tema {
    // Superfícies
    static let fundo            = Color(claro: 0xF4F6F8, escuro: 0x0B0F14)
    static let superficie       = Color(claro: 0xFFFFFF, escuro: 0x131A22)
    static let superficieAlta   = Color(claro: 0xEEF2F5, escuro: 0x1B2430)
    static let linha            = Color(claro: 0xDCE2E8, escuro: 0x253141)

    // Texto
    static let texto            = Color(claro: 0x0E151C, escuro: 0xE9EEF3)
    static let textoSecundario  = Color(claro: 0x5A6776, escuro: 0x98A6B6)
    static let textoTerciario   = Color(claro: 0x8793A1, escuro: 0x66737F)

    // Marca
    static let primaria         = Color(claro: 0x15627C, escuro: 0x1F7A99)   // azul-petróleo
    static let positivo         = Color(claro: 0x12A06A, escuro: 0x3DDC97)   // menta
    // Estados
    static let atencao          = Color(claro: 0xB7801B, escuro: 0xF2B84B)
    static let erro             = Color(claro: 0xC43C3C, escuro: 0xEF5B5B)
    static let neutro           = Color(claro: 0x7D8A9A, escuro: 0x7D8A9A)

    // Mapa (trajeto por estado)
    static let mapaEmCorrida    = positivo
    static let mapaIndoBuscar   = Color(claro: 0x2A86B0, escuro: 0x4BA8D4)
    static let mapaSemCorrida   = neutro
}

extension Color {
    /// Cor que muda sozinha entre modo claro e escuro.
    init(claro: UInt32, escuro: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: escuro) : UIColor(hex: claro) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Tipografia (fonte do sistema: respeita o tamanho de texto do iPhone)

enum Tipo {
    /// O número que manda na tela (faturamento do turno).
    static let destaque = Font.system(size: 44, weight: .bold, design: .rounded)
    /// Números secundários grandes (R$/h, km).
    static let metrica  = Font.system(.title2, design: .rounded).weight(.semibold)
    static let titulo   = Font.title3.weight(.semibold)
    static let corpo    = Font.body
    static let apoio    = Font.subheadline
    static let legenda  = Font.caption
    /// Rótulo em caixa alta com espaçamento ("FATURAMENTO CONFIRMADO").
    static let rotulo   = Font.caption.weight(.semibold)
}

// MARK: Espaço e forma

enum Espaco {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 20
    static let xl: CGFloat = 32
    /// Margem lateral das telas.
    static let margem: CGFloat = 20
}

enum Raio {
    static let bloco: CGFloat = 14
    static let botao: CGFloat = 12
    static let chip: CGFloat = 999
}

// MARK: - Componentes

/// Rótulo em caixa alta, discreto.
struct RotuloSecao: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto.uppercased())
            .font(Tipo.rotulo)
            .tracking(0.8)
            .foregroundStyle(Tema.textoSecundario)
    }
}

/// Cabeçalho de seção: título + ação opcional à direita.
struct CabecalhoSecao<Acao: View>: View {
    let titulo: String
    let acao: Acao

    init(_ titulo: String, @ViewBuilder acao: () -> Acao) {
        self.titulo = titulo
        self.acao = acao()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            RotuloSecao(titulo)
            Spacer()
            acao
                .font(Tipo.apoio)
                .foregroundStyle(Tema.primaria)
        }
    }
}

extension CabecalhoSecao where Acao == EmptyView {
    init(_ titulo: String) { self.init(titulo) { EmptyView() } }
}

/// Métrica em linha: rótulo à esquerda, valor à direita (com confiança, se houver).
struct LinhaMetrica: View {
    let titulo: String
    let valor: Text

    init(_ titulo: String, _ valor: String) {
        self.titulo = titulo
        self.valor = Text(valor)
    }

    init(_ titulo: String, texto: Text) {
        self.titulo = titulo
        self.valor = texto
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titulo)
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
            Spacer(minLength: Espaco.m)
            valor
                .font(Tipo.corpo.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Tema.texto)
        }
        .padding(.vertical, Espaco.s)
    }
}

/// Métrica em coluna: número médio + rótulo. Pra grades de 2–3 métricas secundárias.
struct MetricaCompacta: View {
    let valor: String
    let rotulo: String
    var confianca: Confianca = .confirmado

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valorTexto)
                .font(Tipo.metrica)
                .monospacedDigit()
                .foregroundStyle(confianca == .estimado ? Tema.atencao : Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(rotulo)
                .font(Tipo.legenda)
                .foregroundStyle(Tema.textoSecundario)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valorTexto: String {
        switch confianca {
        case .confirmado:    return valor
        case .estimado:      return "≈ " + valor
        case .indeterminado: return "—"
        }
    }
}

/// Estado de operação: ponto colorido + texto. Discreto, sem caixa.
struct PontoEstado: View {
    let texto: String
    let cor: Color
    var pulsando = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(cor)
                .frame(width: 8, height: 8)
                .opacity(pulsando ? 0.9 : 1)
            Text(texto)
                .font(Tipo.legenda.weight(.medium))
                .foregroundStyle(Tema.textoSecundario)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Botão principal (Iniciar turno). Cheio, cor da marca por padrão.
struct BotaoPrimario: ButtonStyle {
    var cor: Color = Tema.primaria

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(cor.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: Raio.botao))
            .foregroundStyle(.white)
    }
}

/// Botão secundário (Pausar, Abastecimento). Contorno leve, sem preenchimento forte.
struct BotaoSecundario: ButtonStyle {
    var cor: Color = Tema.texto

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Tema.superficieAlta.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: Raio.botao))
            .foregroundStyle(cor)
    }
}

/// Chip de filtro (Mapa, Atividade).
struct ChipFiltro: View {
    let titulo: String
    let ativo: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(titulo)
                .font(Tipo.apoio.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(ativo ? Tema.primaria : Tema.superficieAlta, in: Capsule())
                .foregroundStyle(ativo ? Color.white : Tema.texto)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(ativo ? .isSelected : [])
    }
}

/// Tela/bloco vazio: ícone, frase curta e uma ação opcional.
struct EstadoVazio: View {
    let icone: String
    let titulo: String
    let texto: String
    var acaoTitulo: String?
    var acao: (() -> Void)?

    var body: some View {
        VStack(spacing: Espaco.m) {
            Image(systemName: icone)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Tema.textoTerciario)
            Text(titulo)
                .font(Tipo.titulo)
                .foregroundStyle(Tema.texto)
            Text(texto)
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
                .multilineTextAlignment(.center)
            if let acaoTitulo, let acao {
                Button(acaoTitulo, action: acao)
                    .buttonStyle(BotaoSecundario(cor: Tema.primaria))
                    .frame(maxWidth: 240)
                    .padding(.top, Espaco.s)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaco.xl)
        .padding(.horizontal, Espaco.margem)
    }
}

/// Aviso em linha (erro/atenção/info). Sem caixa pesada: faixa lateral + texto.
struct Aviso: View {
    enum Nivel { case info, atencao, erro }
    let nivel: Nivel
    let texto: String

    private var cor: Color {
        switch nivel {
        case .info:    return Tema.neutro
        case .atencao: return Tema.atencao
        case .erro:    return Tema.erro
        }
    }

    private var icone: String {
        switch nivel {
        case .info:    return "info.circle"
        case .atencao: return "exclamationmark.triangle"
        case .erro:    return "xmark.octagon"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Espaco.s) {
            Image(systemName: icone).foregroundStyle(cor)
            Text(texto)
                .font(Tipo.apoio)
                .foregroundStyle(Tema.texto)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Espaco.m)
        .background(cor.opacity(0.12), in: RoundedRectangle(cornerRadius: Raio.botao))
    }
}

/// Carregando: discreto, com texto do que está acontecendo.
struct Carregando: View {
    let texto: String

    var body: some View {
        HStack(spacing: Espaco.s) {
            ProgressView()
            Text(texto)
                .font(Tipo.apoio)
                .foregroundStyle(Tema.textoSecundario)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaco.l)
    }
}

/// Bloco com título pra gráficos e grupos densos (Atividade/Análises). Superfície leve, sem sombra.
struct BlocoGrafico<Conteudo: View>: View {
    let titulo: String
    var subtitulo: String?
    let conteudo: Conteudo

    init(_ titulo: String, subtitulo: String? = nil, @ViewBuilder conteudo: () -> Conteudo) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            VStack(alignment: .leading, spacing: 2) {
                RotuloSecao(titulo)
                if let subtitulo {
                    Text(subtitulo).font(Tipo.legenda).foregroundStyle(Tema.textoTerciario)
                }
            }
            conteudo
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: Raio.bloco))
    }
}

/// Divisória fina.
struct Divisoria: View {
    var body: some View {
        Rectangle().fill(Tema.linha).frame(height: 1 / UIScreen.main.scale)
    }
}

// MARK: - Estados da operação

extension EstadoMotorista {
    /// Cor do estado no painel e no mapa. Aguardando é neutro de propósito: não é bom nem ruim.
    var cor: Color {
        switch self {
        case .emCorrida:  return Tema.positivo
        case .aCaminho:   return Tema.mapaIndoBuscar
        case .aguardando: return Tema.neutro
        case .pausado:    return Tema.atencao
        case .semLeitura: return Tema.textoTerciario   // indeterminado, não é erro
        }
    }
}
