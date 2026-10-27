package com.elias.app99

import java.text.Normalizer
import java.util.Locale

data class OfertaCorrida(
    val valor: Double,               // R$ que aparece na oferta
    val kmAtePassageiro: Double,     // distância de busca
    val kmViagem: Double,            // distância até o destino
    val minAtePassageiro: Int?,
    val minViagem: Int?,
    val notaPassageiro: Double?,     // null se não achar (ex.: passageiro novo)
    val textoBruto: String
)

/** Lê a oferta da 99 a partir das linhas de texto do OCR (porte do ParserOferta99 do iOS). */
object ParserOferta99 {

    // \x24 = '$' (evita template do Kotlin). R$ 12,50 | RS 12,50 (OCR às vezes lê $ como S ou 5)
    private val regexValor = Regex("""R\s?[\x24S5]\s?(\d{1,3}(?:\.\d{3})*[,.]\d{2})""")

    // 1,2 km | 800 m
    private val regexDistancia = Regex("""(\d+(?:[.,]\d+)?)\s?(km|m)(?![a-zà-ú])""", RegexOption.IGNORE_CASE)

    // "7 min (2,1 km)" — aceita erros comuns do OCR: "mn"/"m1n", "(" lido como "[", "{" ou "C"
    private val regexTrecho = Regex(
        """(\d{1,3})\s?m[il1]?n\.?\s*[(\[{C]?\s*(\d{1,3}(?:[.,]\d{1,2})?)\s?(km|m)(?![a-zà-ú])""",
        RegexOption.IGNORE_CASE
    )

    // Nota 1,00–5,00 sem R$ antes nem "x" depois (multiplicador "1,3x")
    private val regexNota = Regex("""(?<![\d,.\x24])([1-5][,.]\d{2})(?![\d,.]|\s?x)""")
    private val regexReais = Regex("""R\s?[\x24S5]""")
    private val regexMinutos = Regex("""(\d+)\s?min""", RegexOption.IGNORE_CASE)

    fun extrair(linhas: List<String>): OfertaCorrida? {
        val texto = linhas.joinToString("\n")

        // Maior valor em R$ = valor da corrida (evita bônus "+R$ 2,00" ou "R$ 1,90/km")
        val valor = capturas(regexValor, texto).mapNotNull { converterReais(it) }.maxOrNull() ?: return null

        val nota = extrairNota(linhas)
        val trechos = capturasTrecho(texto).filter { it.second > 0 && it.second < 200 }
        if (trechos.size >= 2) {
            return OfertaCorrida(
                valor, trechos[0].second, trechos[1].second,
                trechos[0].first, trechos[1].first, nota, texto
            )
        }

        // Plano B: quaisquer duas distâncias, na ordem de leitura
        val distancias = capturasDistancia(texto).filter { it > 0 && it < 200 }
        if (distancias.size < 2) return null

        val minutos = capturas(regexMinutos, texto).mapNotNull { it.toIntOrNull() }
        return OfertaCorrida(
            valor, distancias[0], distancias[1],
            minutos.getOrNull(0), minutos.getOrNull(1), nota, texto
        )
    }

    /** Maior valor em R$ da tela, em centavos (valor final na tela de fim de corrida). */
    fun maiorValorCent(linhas: List<String>): Int? =
        capturas(regexValor, linhas.joinToString("\n")).mapNotNull { converterReais(it) }.maxOrNull()
            ?.let { Math.round(it * 100).toInt() }

    /** 1º: linha com "corridas" (ex.: "4,95 • +999 corridas"), sem R$. 2º: linha que é só a nota. */
    fun extrairNota(linhas: List<String>): Double? {
        fun notaEm(s: String): Double? {
            val m = regexNota.find(s) ?: return null
            val v = m.groupValues[1].replace(',', '.').toDoubleOrNull() ?: return null
            return if (v <= 5) v else null
        }

        for (linha in linhas) {
            if (linha.lowercase().contains("corridas") && regexReais.find(linha) == null) {
                notaEm(linha)?.let { return it }
            }
        }
        val enfeites = " \t•·*★☆⭐"
        for (linha in linhas) {
            val limpa = linha.trim { it in enfeites }
            if (limpa.length == 4) notaEm(limpa)?.let { return it }
        }
        return null
    }

    private fun capturas(regex: Regex, texto: String): List<String> =
        regex.findAll(texto).map { it.groupValues[1] }.toList()

    private fun capturasTrecho(texto: String): List<Pair<Int?, Double>> =
        regexTrecho.findAll(texto).mapNotNull { m ->
            val v = m.groupValues[2].replace(',', '.').toDoubleOrNull() ?: return@mapNotNull null
            val unidade = m.groupValues[3].lowercase()
            Pair(m.groupValues[1].toIntOrNull(), if (unidade == "m") v / 1000 else v)
        }.toList()

    private fun capturasDistancia(texto: String): List<Double> =
        regexDistancia.findAll(texto).mapNotNull { m ->
            val v = m.groupValues[1].replace(',', '.').toDoubleOrNull() ?: return@mapNotNull null
            if (m.groupValues[2].lowercase() == "m") v / 1000 else v
        }.toList()

    /** "1.234,56" / "12,50" / "12.50" → Double */
    private fun converterReais(s: String): Double? {
        val inteiro = s.dropLast(3).replace(".", "")
        return "$inteiro.${s.takeLast(2)}".toDoubleOrNull()
    }
}

/** Reconhece as telas da 99 depois do aceite, pelos textos dos botões. */
enum class TelaCorrida {
    A_CAMINHO,   // "Cheguei no local"
    EMBARQUE,    // "Iniciar corrida": no local, esperando o passageiro
    A_BORDO,     // "Finalizar corrida": passageiro a bordo (NÃO é fim)
    FIM,         // tela de corrida encerrada / avaliação
    CANCELADA,
    OUTRA;

    companion object {
        /** Só vale como botão/título: linha curta que começa com o texto, não frase que o cita no meio. */
        fun identificar(linhas: List<String>): TelaCorrida {
            val botoes = linhas.map { normalizar(it) }

            fun temLinha(textos: List<String>, folga: Int = 12) =
                botoes.any { linha -> textos.any { linha.startsWith(it) && linha.length <= it.length + folga } }

            val avisosCancelamento = listOf("cancelou", "corrida cancelada", "viagem cancelada")
            if (botoes.any { l -> l.length <= 60 && avisosCancelamento.any { l.contains(it) } }) return CANCELADA
            if (temLinha(
                    listOf(
                        "corrida finalizada", "viagem finalizada", "corrida concluida", "viagem concluida",
                        "corrida encerrada", "avalie o passageiro", "avalie seu passageiro",
                        "como foi a corrida", "como foi sua corrida", "como foi a viagem"
                    ), folga = 20
                )
            ) return FIM
            if (temLinha(listOf("finalizar corrida", "finalizar viagem", "encerrar corrida"))) return A_BORDO
            if (temLinha(listOf("iniciar corrida", "iniciar viagem"))) return EMBARQUE
            if (temLinha(listOf("cheguei"))) return A_CAMINHO
            return OUTRA
        }

        /** Minúsculas, sem acento, só letras/números/espaços, sem espaço nas pontas. */
        private fun normalizar(s: String): String {
            val semAcento = Normalizer.normalize(s, Normalizer.Form.NFD)
                .replace(Regex("\\p{M}+"), "")
                .lowercase(Locale.ROOT)
            val limpo = semAcento.map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("")
            return limpo.split(' ').filter { it.isNotEmpty() }.joinToString(" ")
        }
    }
}
