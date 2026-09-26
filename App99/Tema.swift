import SwiftUI
import UIKit

// Apex: tokens e peças de interface.
// Menta só para dinheiro confirmado e operação ok. Oferta nunca em menta.
// Hierarquia por tipografia e espaço, não por caixas.

// MARK: - Cores

enum Tema {
    static let fundo            = Color(claro: 0xF5F7F9, escuro: 0x0D0F12)
    static let superficie       = Color(claro: 0xFFFFFF, escuro: 0x16191E)
    static let superficieAlta   = Color(claro: 0xE8ECF0, escuro: 0x1E222A)
    static let linha            = Color(claro: 0xDDE3E8, escuro: 0x232730)

    static let texto            = Color(claro: 0x0E151C, escuro: 0xE9EDF2)
    static let textoSecundario  = Color(claro: 0x5A6776, escuro: 0x9AA3AE)
    static let textoTerciario   = Color(claro: 0x8C97A4, escuro: 0x5E6672)

    static let primaria         = Color(claro: 0x15627C, escuro: 0x2B8FB3)
    static let positivo         = Color(claro: 0x0E9F6E, escuro: 0x10B981)
    static let atencao          = Color(claro: 0xB7801B, escuro: 0xF2B84B)
    static let erro             = Color(claro: 0xC43C3C, escuro: 0xEF5B5B)
    static let neutro           = Color(claro: 0x64748B, escuro: 0x64748B)

    static let mapaEmCorrida    = positivo
    static let mapaIndoBuscar   = Color(claro: 0xC98A12, escuro: 0xF4B63F)
    static let mapaSemCorrida   = Color(claro: 0x2F6FDB, escuro: 0x3B82F6)
    static let abastecimento    = Color(claro: 0x7B5CC4, escuro: 0xA58BF0)
}

extension Color {
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

// MARK: - Tipografia, espaço, forma

enum Tipo {
    static let heroi    = Font.system(size: 50, weight: .bold, design: .rounded)
    static let destaque = Font.system(size: 40, weight: .bold, design: .rounded)
    static let porHora  = Font.system(size: 28, weight: .bold, design: .rounded)
    static let metrica  = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let valor    = Font.system(.body, design: .rounded).weight(.semibold)
    static let titulo   = Font.title3.weight(.semibold)
    static let corpo    = Font.body
    static let apoio    = Font.subheadline
    static let legenda  = Font.caption
    static let rotulo   = Font.caption2.weight(.semibold)
}

enum Espaco {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
    static let margem: CGFloat = 20
}

enum Raio {
    static let bloco: CGFloat = 16
    static let botao: CGFloat = 14
}

// MARK: - Texto

struct RotuloSecao: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto.uppercased())
            .font(Tipo.rotulo)
            .tracking(1)
            .foregroundStyle(Tema.textoTerciario)
    }
}

/// Seção sem caixa: rótulo pequeno, ação opcional à direita e o conteúdo.
struct Secao<Conteudo: View, Acao: View>: View {
    let titulo: String
    let acao: Acao
    let conteudo: Conteudo

    init(_ titulo: String, @ViewBuilder acao: () -> Acao, @ViewBuilder conteudo: () -> Conteudo) {
        self.titulo = titulo
        self.acao = acao()
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            HStack(alignment: .firstTextBaseline) {
                RotuloSecao(titulo)
                Spacer()
                acao
                    .font(Tipo.legenda.weight(.semibold))
                    .foregroundStyle(Tema.primaria)
            }
            conteudo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Secao where Acao == EmptyView {
    init(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) {
        self.init(titulo, acao: { EmptyView() }, conteudo: conteudo)
    }
}

// MARK: - Números

/// Número + rótulo pequeno. "≈" em âmbar quando estimado, "—" quando não há dado.
struct Metrica: View {
    let valor: String
    let rotulo: String
    var estimado = false

    init(_ valor: String, _ rotulo: String, estimado: Bool = false) {
        self.valor = valor
        self.rotulo = rotulo
        self.estimado = estimado
    }

    init(_ medida: Medida, _ rotulo: String, formatar: (Double) -> String) {
        self.init(medida.valor.map(formatar) ?? "—", rotulo,
                  estimado: medida.valor != nil && medida.confianca == .estimado)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((estimado ? "≈ " : "") + valor)
                .font(Tipo.metrica)
                .monospacedDigit()
                .foregroundStyle(estimado ? Tema.atencao : Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(rotulo)
                .font(Tipo.legenda)
                .foregroundStyle(Tema.textoSecundario)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct GradeMetricas<Conteudo: View>: View {
    var colunas = 3
    let conteudo: Conteudo

    init(colunas: Int = 3, @ViewBuilder conteudo: () -> Conteudo) {
        self.colunas = colunas
        self.conteudo = conteudo()
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Espaco.m, alignment: .topLeading), count: colunas),
                  alignment: .leading, spacing: Espaco.l) {
            conteudo
        }
    }
}

struct LinhaMetrica: View {
    let titulo: String
    let valor: String
    var cor: Color = Tema.texto

    init(_ titulo: String, _ valor: String, cor: Color = Tema.texto) {
        self.titulo = titulo
        self.valor = valor
        self.cor = cor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titulo).font(Tipo.apoio).foregroundStyle(Tema.textoSecundario)
            Spacer(minLength: Espaco.m)
            Text(valor).font(Tipo.apoio.weight(.medium)).monospacedDigit().foregroundStyle(cor)
        }
        .padding(.vertical, 10)
    }
}

extension Medida {
    func texto(_ formatar: (Double) -> String) -> String {
        guard let v = valor, confianca != .indeterminado else { return "—" }
        return (confianca == .estimado ? "≈ " : "") + formatar(v)
    }
}

// MARK: - Estado

struct PontoEstado: View {
    let texto: String
    let cor: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(cor).frame(width: 9, height: 9)
            Text(texto)
                .font(Tipo.apoio.weight(.semibold))
                .foregroundStyle(Tema.texto)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Selo: View {
    let texto: String
    let cor: Color

    var body: some View {
        Text(texto)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(cor.opacity(0.16), in: Capsule())
            .foregroundStyle(cor)
    }
}

/// Só para problema que pede ação do motorista.
struct Alerta: View {
    let texto: String
    var acaoTitulo: String?
    var acao: (() -> Void)?

    var body: some View {
        HStack(spacing: Espaco.m) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tema.atencao)
            Text(texto).font(Tipo.apoio.weight(.medium)).foregroundStyle(Tema.texto)
            Spacer(minLength: Espaco.s)
            if let acaoTitulo, let acao {
                Button(acaoTitulo, action: acao)
                    .font(Tipo.apoio.weight(.semibold))
                    .foregroundStyle(Tema.primaria)
            }
        }
        .padding(.horizontal, Espaco.m)
        .padding(.vertical, 12)
        .background(Tema.atencao.opacity(0.12), in: RoundedRectangle(cornerRadius: Raio.botao))
    }
}

// MARK: - Ações

struct BotaoPrimario: ButtonStyle {
    var cor: Color = Tema.primaria

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(cor.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: Raio.botao))
            .foregroundStyle(.white)
    }
}

struct BotaoSecundario: ButtonStyle {
    var cor: Color = Tema.texto

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Tema.superficieAlta.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: Raio.botao))
            .foregroundStyle(cor)
    }
}

struct ChipFiltro: View {
    let titulo: String
    let ativo: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(titulo)
                .font(Tipo.apoio.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(ativo ? Tema.positivo.opacity(0.14) : Tema.superficie, in: Capsule())
                .overlay(Capsule().stroke(ativo ? Tema.positivo : Tema.linha, lineWidth: 1))
                .foregroundStyle(ativo ? Tema.positivo : Tema.textoSecundario)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(ativo ? .isSelected : [])
    }
}

struct FiltrosChips<Valor: Hashable>: View {
    let opcoes: [Valor]
    let nome: (Valor) -> String
    @Binding var selecao: Valor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espaco.s) {
                ForEach(opcoes, id: \.self) { o in
                    ChipFiltro(titulo: nome(o), ativo: selecao == o) { selecao = o }
                }
            }
            .padding(.horizontal, Espaco.margem)
        }
    }
}

struct LinhaNavegacao: View {
    let titulo: String
    let icone: String
    var valor: String = ""

    init(_ titulo: String, _ icone: String, _ valor: String = "") {
        self.titulo = titulo
        self.icone = icone
        self.valor = valor
    }

    var body: some View {
        HStack(spacing: Espaco.m) {
            Image(systemName: icone)
                .foregroundStyle(Tema.primaria)
                .frame(width: 24)
            Text(titulo).font(Tipo.corpo).foregroundStyle(Tema.texto)
            Spacer(minLength: Espaco.s)
            Text(valor).font(Tipo.apoio).monospacedDigit().foregroundStyle(Tema.textoSecundario)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.textoTerciario)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct EstadoVazio: View {
    let icone: String
    let titulo: String

    var body: some View {
        VStack(spacing: Espaco.m) {
            Image(systemName: icone)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Tema.textoTerciario)
            Text(titulo)
                .font(Tipo.apoio.weight(.medium))
                .foregroundStyle(Tema.textoSecundario)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaco.xxl)
    }
}

struct Divisoria: View {
    var body: some View {
        Rectangle().fill(Tema.linha).frame(height: 1 / UIScreen.main.scale)
    }
}

// MARK: - Barras

/// Tempo por estado numa barra só, com legenda curta.
struct BarraEstados: View {
    let tempos: [EstadoMotorista: TimeInterval]
    static let ordem: [EstadoMotorista] = [.emCorrida, .aCaminho, .aguardando, .pausado, .semLeitura]

    private struct Fatia: Identifiable {
        let estado: EstadoMotorista
        let segundos: TimeInterval
        var id: EstadoMotorista { estado }
    }

    private var itens: [Fatia] {
        Self.ordem.compactMap { e in tempos[e].flatMap { $0 >= 30 ? Fatia(estado: e, segundos: $0) : nil } }
    }

    var body: some View {
        let lista = itens
        let total = max(1, lista.reduce(0) { $0 + $1.segundos })
        VStack(alignment: .leading, spacing: Espaco.m) {
            GeometryReader { g in
                let util = g.size.width - CGFloat(max(0, lista.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(lista) { item in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.estado.cor)
                            .frame(width: max(4, util * item.segundos / total))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Espaco.s) {
                ForEach(lista) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.estado.cor).frame(width: 7, height: 7)
                        Text(item.estado.nome).font(Tipo.legenda).foregroundStyle(Tema.textoSecundario)
                        Text(String(format: "%.0f%%", item.segundos / total * 100)).font(Tipo.legenda.weight(.semibold))
                            .monospacedDigit().foregroundStyle(Tema.texto)
                    }
                    .accessibilityLabel("\(item.estado.nome): \(Duracao.curta(item.segundos))")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BarraMeta: View {
    let valor: Double
    let meta: Double

    var body: some View {
        let atingida = valor >= meta
        HStack(spacing: Espaco.m) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.superficieAlta)
                    Capsule().fill(atingida ? Tema.positivo : Tema.primaria)
                        .frame(width: g.size.width * min(1, max(0, valor / meta)))
                }
            }
            .frame(height: 6)
            Text("meta \(Formato.reais(meta))")
                .font(Tipo.legenda.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(atingida ? Tema.positivo : Tema.textoSecundario)
                .fixedSize()
        }
    }
}

/// Pílula discreta: valor do ponto tocado num gráfico, status do turno.
struct Pilula: View {
    let texto: String
    var cor: Color = Tema.texto
    var fundo: Color = Tema.superficie

    var body: some View {
        Text(texto)
            .font(Tipo.legenda.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fundo, in: Capsule())
            .overlay(Capsule().stroke(Tema.linha, lineWidth: 1))
            .foregroundStyle(cor)
            .fixedSize()
    }
}

/// Cartão: superfície escura com borda fina.
struct Cartao<Conteudo: View>: View {
    var espaco: CGFloat = 14
    let conteudo: Conteudo

    init(espaco: CGFloat = 14, @ViewBuilder conteudo: () -> Conteudo) {
        self.espaco = espaco
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { conteudo }
            .padding(espaco)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.superficie, in: RoundedRectangle(cornerRadius: Raio.bloco))
            .overlay(RoundedRectangle(cornerRadius: Raio.bloco).stroke(Tema.linha, lineWidth: 1))
    }
}

/// Seletor segmentado: fundo escuro, opção ativa em superfície clara.
struct Segmentos<Valor: Hashable>: View {
    let opcoes: [Valor]
    let nome: (Valor) -> String
    @Binding var selecao: Valor

    var body: some View {
        HStack(spacing: 4) {
            ForEach(opcoes, id: \.self) { o in
                Button { selecao = o } label: {
                    Text(nome(o))
                        .font(Tipo.apoio.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selecao == o ? Tema.superficieAlta : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(selecao == o ? Tema.texto : Tema.textoSecundario)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selecao == o ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tema.linha, lineWidth: 1))
    }
}

// MARK: - Estados da operação

extension EstadoMotorista {
    var cor: Color {
        switch self {
        case .emCorrida:  return Tema.positivo
        case .aCaminho:   return Tema.mapaIndoBuscar
        case .aguardando: return Tema.mapaSemCorrida
        case .pausado:    return Tema.atencao
        case .semLeitura: return Tema.textoTerciario
        }
    }
}

// MARK: - Formatos de tela

extension Datas {
    static func hora(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func corridas(_ n: Int) -> String { n == 1 ? "1 corrida" : "\(n) corridas" }

    /// "Sexta-feira, 25 de setembro"
    static func extensa(_ d: Date) -> String {
        let t = d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// "Sábado, 26 de set." (só a primeira letra maiúscula)
    static func longaTitulo(_ d: Date) -> String {
        let t = d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
