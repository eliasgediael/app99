package com.elias.app99

import java.text.NumberFormat
import java.util.Locale

data class ConfigMoto(
    /** Custo por km rodado (combustível + óleo, pneu, manutenção, desgaste) */
    val custoPorKm: Double = 0.35,
    /** Abaixo disso (R$/km bruto) = recusa */
    val minimoPorKm: Double = 1.80,
    /** Acima disso = corrida boa */
    val bomPorKm: Double = 2.50,
    /** Busca acima disso gera aviso no áudio */
    val alertaBuscaKm: Double = 3.0,
    /** Passageiro com nota abaixo disso = recusa, mesmo com valor bom */
    val notaMinima: Double = 4.90,
    /** Lucro (valor − custo da moto) abaixo disso = ruim. 0 = sem esse critério */
    val lucroMinimo: Double = 0.0
)

enum class Veredito(val falado: String, val emoji: String) {
    BOA("Corrida boa", "🟢"),
    ACEITAVEL("Aceitável", "🟡"),
    RUIM("Recusa", "🔴")
}

data class AnaliseCorrida(
    val oferta: OfertaCorrida,
    val kmTotal: Double,
    val ganhoPorKm: Double,
    val custoEstimado: Double,
    val lucro: Double,
    val lucroPorKm: Double,
    val ganhoPorHora: Double?,
    val veredito: Veredito,
    val buscaLonga: Boolean,
    val notaBaixa: Boolean
) {
    /** Frase curta, veredito primeiro — você decide no primeiro segundo. */
    val fraseFalada: String
        get() {
            val partes = mutableListOf(veredito.falado)
            val nota = oferta.notaPassageiro
            if (notaBaixa && nota != null) partes[0] += ", passageiro nota ${Formato.nota(nota)}"
            partes.add("${Fala.reais(ganhoPorKm)} por quilômetro")
            partes.add("lucro de ${Fala.reais(lucro)}")
            partes.add("${Fala.km(kmTotal)} no total")
            if (buscaLonga) partes.add("busca de ${Fala.km(oferta.kmAtePassageiro)}")
            return partes.joinToString(". ") + "."
        }
}

class CalculadoraCorrida(private val config: ConfigMoto) {

    fun analisar(o: OfertaCorrida): AnaliseCorrida {
        val kmTotal = o.kmAtePassageiro + o.kmViagem
        val ganhoPorKm = if (kmTotal > 0) o.valor / kmTotal else 0.0
        val custo = kmTotal * config.custoPorKm
        val lucro = o.valor - custo
        val lucroPorKm = if (kmTotal > 0) lucro / kmTotal else 0.0

        var ganhoPorHora: Double? = null
        val a = o.minAtePassageiro
        val v = o.minViagem
        if (a != null && v != null && a + v > 0) ganhoPorHora = lucro / ((a + v) / 60.0)

        var veredito = when {
            ganhoPorKm >= config.bomPorKm -> Veredito.BOA
            ganhoPorKm >= config.minimoPorKm -> Veredito.ACEITAVEL
            else -> Veredito.RUIM
        }

        val notaBaixa = o.notaPassageiro?.let { it < config.notaMinima } ?: false
        if (notaBaixa) veredito = Veredito.RUIM
        if (config.lucroMinimo > 0 && lucro < config.lucroMinimo) veredito = Veredito.RUIM

        return AnaliseCorrida(
            o, kmTotal, ganhoPorKm, custo, lucro, lucroPorKm, ganhoPorHora,
            veredito, o.kmAtePassageiro >= config.alertaBuscaKm, notaBaixa
        )
    }
}

/** Números em formato "falável": "2,10" vira "2 reais e 10". */
object Fala {
    fun reais(valor: Double): String {
        val centavosTotais = Math.round(Math.abs(valor) * 100).toInt()
        val r = centavosTotais / 100
        val c = centavosTotais % 100
        var s = if (r == 0 && c > 0) {
            "$c centavos"
        } else {
            (if (r == 1) "1 real" else "$r reais") + (if (c > 0) " e $c" else "")
        }
        if (valor < 0) s = "menos $s"
        return s
    }

    fun km(valor: Double): String {
        val f = NumberFormat.getNumberInstance(Locale("pt", "BR"))
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return "${f.format(valor)} quilômetros"
    }
}

/** Formatação pra tela e notificação. */
object Formato {
    private val ptBR = Locale("pt", "BR")

    fun reais(v: Double): String = NumberFormat.getCurrencyInstance(ptBR).format(v)
    fun nota(v: Double): String = String.format(Locale.US, "%.2f", v).replace('.', ',')
    fun km(v: Double): String = String.format(Locale.US, "%.1f km", v).replace('.', ',')

    /** 0,35 / 4,9 / 250 (sem zeros sobrando) */
    fun numero(v: Double): String {
        val f = NumberFormat.getNumberInstance(ptBR)
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.isGroupingUsed = false
        return f.format(v)
    }

    fun inteiro(v: Double): String = Math.round(v).toString()

    /** 3h 12min · 45 min */
    fun duracao(ms: Long): String {
        val min = ms / 60_000
        return if (min < 60) "$min min" else "${min / 60}h ${String.format(Locale.US, "%02d", min % 60)}min"
    }
}
