package com.elias.app99

import org.json.JSONObject
import java.util.TimeZone

// MARK: Estados e confiança

enum class EstadoCorrida(val v: Int, val nome: String) {
    ACEITA(1, "ACEITA"),
    A_CAMINHO(2, "A_CAMINHO"),
    PASSAGEIRO_A_BORDO(3, "PASSAGEIRO_A_BORDO"),
    EM_CORRIDA(4, "EM_CORRIDA"),
    FIM_DETECTADO(5, "FIM_DE_CORRIDA_DETECTADO"),
    CONFIRMADA(6, "CONFIRMADA"),
    ESTIMADA(7, "ESTIMADA"),
    INDETERMINADA(8, "INDETERMINADA"),
    CANCELADA(9, "CANCELADA");

    companion object {
        fun de(v: Int) = entries.firstOrNull { it.v == v }
    }
}

enum class Confianca(val v: Int, val nome: String) {
    CONFIRMADO(1, "CONFIRMADO"),
    ESTIMADO(2, "ESTIMADO"),
    INDETERMINADO(3, "INDETERMINADO");

    companion object {
        fun de(v: Int) = entries.firstOrNull { it.v == v }
    }
}

enum class TipoEvento(val v: Int, val nome: String) {
    LEITURA_INICIADA(1, "LEITURA_INICIADA"),
    LEITURA_ENCERRADA(2, "LEITURA_ENCERRADA"),
    OFERTA_DETECTADA(3, "OFERTA_DETECTADA"),
    OFERTA_SAIU_DA_TELA(4, "OFERTA_SAIU_DA_TELA"),
    ACEITE_DETECTADO(5, "ACEITE_DETECTADO"),
    TELA_EMBARQUE(6, "CHEGOU_NO_EMBARQUE"),
    PASSAGEIRO_A_BORDO(7, "PASSAGEIRO_A_BORDO"),
    FIM_DETECTADO(8, "FIM_DE_CORRIDA_DETECTADO"),
    CANCELAMENTO_DETECTADO(9, "CANCELAMENTO_DETECTADO"),
    TRANSICAO(10, "ESTADO"),
    FATURAMENTO_CONFIRMADO(11, "FATURAMENTO_CONFIRMADO"),
    FATURAMENTO_ESTIMADO(12, "FATURAMENTO_ESTIMADO"),
    SEM_FATURAMENTO(13, "SEM_FATURAMENTO"),
    DIA_ZERADO(14, "DIA_ZERADO");

    companion object {
        fun de(v: Int) = entries.firstOrNull { it.v == v }
    }
}

enum class OrigemEvento(val v: Int, val nome: String) {
    TELA(1, "tela"),
    INFERENCIA(2, "inferência"),
    SISTEMA(3, "sistema"),
    USUARIO(4, "você");

    companion object {
        fun de(v: Int) = entries.firstOrNull { it.v == v }
    }
}

/** Por que o motor tomou a decisão. `extra` complementa alguns motivos. */
enum class Motivo(val v: Int) {
    NENHUM(0),
    LIDO_NA_TELA(1),
    OFERTA_LIGADA_AO_ACEITE(2),
    ACEITE_SEM_OFERTA(3),
    ACEITE_OFERTA_AMBIGUA(4),
    A_BORDO_IMPLICA_EM_CORRIDA(5),
    A_BORDO_SEM_ACEITE(6),
    FIM_SEM_CORRIDA_ABERTA(7),
    EVIDENCIA_COMPLETA(8),
    EVIDENCIA_INCOMPLETA(9),
    SUBSTITUIDA_POR_NOVO_ACEITE(10),
    CANCELADA_NA_TELA(11),
    OFERTA_SAIU_SEM_ACEITE(12),
    VALOR_FINAL_LIDO_NA_TELA(13),
    TEMPO_ESGOTADO(14),
    LEITURA_ENCERRADA(15),
    ZERADO_PELO_USUARIO(16),
    CANCELAMENTO_SEM_CORRIDA(17),
    MESMA_CORRIDA_NA_TELA(18),
    OFERTA_LIGADA_FRACA(19),
    REGISTRADO_PELO_USUARIO(20),
    OFERTA_CANCELADA_NA_TELA(21),
    OFERTA_ACEITA_DURANTE_CORRIDA(22),
    FIM_INFERIDO_POR_NOVO_ACEITE(23),
    ACEITE_INFERIDO_PELO_FIM(24);

    fun texto(extra: Int): String = when (this) {
        NENHUM -> ""
        LIDO_NA_TELA -> "Lido na tela."
        OFERTA_LIGADA_AO_ACEITE -> "Aceite veio $extra s depois desta oferta sair da tela, sem outra oferta no meio."
        ACEITE_SEM_OFERTA -> "Nenhuma oferta nos 60 s antes do aceite: valor desconhecido."
        ACEITE_OFERTA_AMBIGUA -> "Outra oferta apareceu no meio: não dá pra saber qual foi aceita. Valor desconhecido."
        A_BORDO_IMPLICA_EM_CORRIDA -> "Inferido: passageiro a bordo ⇒ corrida em andamento."
        A_BORDO_SEM_ACEITE -> "Passageiro a bordo sem aceite detectado antes."
        FIM_SEM_CORRIDA_ABERTA -> "Tela de fim sem corrida aberta: ignorada."
        EVIDENCIA_COMPLETA -> "Aceite + valor + passageiro a bordo + fim detectados."
        EVIDENCIA_INCOMPLETA -> "Faltou: " + Falta.descrever(extra) + "."
        SUBSTITUIDA_POR_NOVO_ACEITE -> "Novo aceite antes do passageiro embarcar nesta."
        CANCELADA_NA_TELA -> "Cancelamento lido na tela."
        OFERTA_SAIU_SEM_ACEITE -> "Oferta saiu da tela. Sem aceite, não fatura."
        VALOR_FINAL_LIDO_NA_TELA -> "Valor final lido na tela de fim."
        TEMPO_ESGOTADO -> "Corrida aberta há mais de 3 h: encerrada com o que se sabe."
        LEITURA_ENCERRADA -> "Leitura desligada com a corrida aberta: encerrada com o que se sabe."
        ZERADO_PELO_USUARIO -> "Números de hoje apagados pelo usuário."
        CANCELAMENTO_SEM_CORRIDA -> "Cancelamento sem corrida aceita aberta."
        MESMA_CORRIDA_NA_TELA -> "Tela da corrida que já estava aberta."
        OFERTA_LIGADA_FRACA -> "Aceite veio $extra s depois desta oferta sair da tela: associação só ESTIMADA (confirmada é até 30 s)."
        REGISTRADO_PELO_USUARIO -> "Registrado por você."
        OFERTA_CANCELADA_NA_TELA -> "Aviso de cancelamento logo depois desta oferta sair: vale pra oferta, não pra sua corrida."
        OFERTA_ACEITA_DURANTE_CORRIDA ->
            if (extra > 1) "Oferta aceita durante a corrida anterior, mas havia $extra na fila: associação só ESTIMADA."
            else "Oferta aceita durante a corrida anterior (saiu da tela sem aviso de cancelamento)."
        FIM_INFERIDO_POR_NOVO_ACEITE -> "Inferido: a tela de aceite da próxima corrida apareceu ⇒ esta terminou."
        ACEITE_INFERIDO_PELO_FIM -> "Inferido: corrida aceita durante a anterior; a tela de aceite não foi vista."
    }

    companion object {
        fun de(v: Int) = entries.firstOrNull { it.v == v } ?: NENHUM
    }
}

/** Evidências que podem faltar pra confirmar uma corrida (máscara de bits). */
object Falta {
    const val ACEITE = 1
    const val VALOR = 2
    const val A_BORDO = 4
    const val FIM = 8
    const val LIGACAO = 16   // oferta↔aceite só ESTIMADA

    fun descrever(mascara: Int): String {
        val partes = mutableListOf<String>()
        if (mascara and ACEITE != 0) partes.add("aceite")
        if (mascara and VALOR != 0) partes.add("valor (oferta ligada)")
        if (mascara and A_BORDO != 0) partes.add("passageiro a bordo")
        if (mascara and FIM != 0) partes.add("tela de fim")
        if (mascara and LIGACAO != 0) partes.add("associação confirmada oferta↔aceite")
        return if (partes.isEmpty()) "nada" else partes.joinToString(", ")
    }
}

// MARK: Evento da linha do tempo

data class EventoLinha(
    var seq: Int = 0,
    var em: Long = 0,                        // segundos desde 1970
    val tipo: TipoEvento,
    val origem: OrigemEvento,
    var corrida: Int = 0,                    // id da corrida (0 = nenhuma)
    var estadoAnterior: EstadoCorrida? = null,
    var estadoNovo: EstadoCorrida? = null,
    var confianca: Confianca? = null,
    var motivo: Motivo = Motivo.NENHUM,
    var extra: Int = 0,
    var valorCent: Int = 0,
    var buscaM: Int = 0,
    var viagemM: Int = 0,
    var nota100: Int = 0,
    var oferta: Int = 0,                     // id da oferta (0 = nenhuma)
    var minutos: Int = 0,                    // busca × 1000 + viagem (0 = não lido)
    var lat: Double? = null,                 // posição do GPS no momento (só com turno e sinal)
    var lon: Double? = null
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("seq", seq); put("em", em); put("tipo", tipo.v); put("origem", origem.v)
        put("corrida", corrida)
        put("ant", estadoAnterior?.v ?: 0); put("novo", estadoNovo?.v ?: 0)
        put("conf", confianca?.v ?: 0); put("motivo", motivo.v); put("extra", extra)
        put("valorCent", valorCent); put("buscaM", buscaM); put("viagemM", viagemM)
        put("nota100", nota100); put("oferta", oferta); put("minutos", minutos)
        lat?.let { put("lat", it) }
        lon?.let { put("lon", it) }
    }

    companion object {
        fun deJson(j: JSONObject): EventoLinha? {
            val tipo = TipoEvento.de(j.optInt("tipo")) ?: return null
            val origem = OrigemEvento.de(j.optInt("origem")) ?: return null
            return EventoLinha(
                seq = j.optInt("seq"), em = j.optLong("em"), tipo = tipo, origem = origem,
                corrida = j.optInt("corrida"),
                estadoAnterior = EstadoCorrida.de(j.optInt("ant")),
                estadoNovo = EstadoCorrida.de(j.optInt("novo")),
                confianca = Confianca.de(j.optInt("conf")),
                motivo = Motivo.de(j.optInt("motivo")), extra = j.optInt("extra"),
                valorCent = j.optInt("valorCent"), buscaM = j.optInt("buscaM"),
                viagemM = j.optInt("viagemM"), nota100 = j.optInt("nota100"),
                oferta = j.optInt("oferta"), minutos = j.optInt("minutos"),
                lat = if (j.has("lat")) j.optDouble("lat") else null,
                lon = if (j.has("lon")) j.optDouble("lon") else null
            )
        }
    }
}

// MARK: Totais do dia

data class Dia(
    val dia: Int,                    // dias desde 01/01/1970 no fuso local
    val faturadoCent: Int = 0,       // soma das corridas CONFIRMADAS (bruto)
    val custoCent: Int = 0,          // km × custo por km das confirmadas
    val corridas: Int = 0,           // confirmadas
    val metros: Int = 0,
    val ofertas: Int = 0,            // ofertas diferentes que apareceram
    val segundos: Int = 0,           // tempo com a leitura ligada
    val estimadas: Int = 0,          // ESTIMADAS (fora do faturamento principal)
    val estimadoCent: Int = 0
) {
    val faturado get() = faturadoCent / 100.0
    val estimado get() = estimadoCent / 100.0
    val custo get() = custoCent / 100.0
    val lucro get() = faturado - custo
    val km get() = metros / 1000.0
    val horas get() = segundos / 3600.0
    val porKm: Double? get() = if (km > 0) faturado / km else null
    val lucroPorHora: Double? get() = if (segundos >= 60) lucro / horas else null

    fun toJson(): JSONObject = JSONObject().apply {
        put("dia", dia); put("faturadoCent", faturadoCent); put("custoCent", custoCent)
        put("corridas", corridas); put("metros", metros); put("ofertas", ofertas)
        put("segundos", segundos); put("estimadas", estimadas); put("estimadoCent", estimadoCent)
    }

    companion object {
        fun numero(ms: Long = System.currentTimeMillis()): Int {
            val fuso = TimeZone.getDefault().getOffset(ms) / 1000L
            return Math.floorDiv(ms / 1000 + fuso, 86_400L).toInt()
        }

        fun deJson(j: JSONObject) = Dia(
            dia = j.optInt("dia"), faturadoCent = j.optInt("faturadoCent"), custoCent = j.optInt("custoCent"),
            corridas = j.optInt("corridas"), metros = j.optInt("metros"), ofertas = j.optInt("ofertas"),
            segundos = j.optInt("segundos"), estimadas = j.optInt("estimadas"), estimadoCent = j.optInt("estimadoCent")
        )
    }
}
