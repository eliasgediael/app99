package com.elias.app99

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Corrida montada a partir da linha do tempo (a mesma fonte do motor: nada é guardado em dobro).
 * Tempos em segundos desde 1970, como nos eventos.
 */
data class CorridaResumo(
    val id: Int,
    val aceiteEm: Long? = null,
    val aBordoEm: Long? = null,
    val fimEm: Long? = null,
    val encerradaEm: Long? = null,
    val confianca: Confianca? = null,
    val cancelada: Boolean = false,
    val valorOfertaCent: Int? = null,
    val valorFinalCent: Int? = null,
    val buscaM: Int = 0,
    val viagemM: Int = 0,
    val nota: Double? = null,
    val minutos: Int = 0
) {
    val confirmada get() = confianca == Confianca.CONFIRMADO
    val estimada get() = confianca == Confianca.ESTIMADO
    val feita get() = confirmada || estimada
    val valorCent: Int? get() = valorFinalCent ?: valorOfertaCent
    val valor: Double? get() = valorCent?.let { it / 100.0 }
    val km: Double? get() = (buscaM + viagemM).takeIf { it > 0 }?.let { it / 1000.0 }
    val termino: Long? get() = fimEm ?: encerradaEm
    val dia: LocalDate? get() = termino?.let { Instant.ofEpochSecond(it).atZone(ZoneId.systemDefault()).toLocalDate() }

    /** A oferta como a 99 mostrou, pra classificar com os seus critérios. */
    fun oferta(): OfertaCorrida? {
        val v = valorOfertaCent ?: return null
        if (buscaM + viagemM <= 0) return null
        return OfertaCorrida(
            valor = v / 100.0, kmAtePassageiro = buscaM / 1000.0, kmViagem = viagemM / 1000.0,
            minAtePassageiro = (minutos / 1000).takeIf { minutos > 0 },
            minViagem = (minutos % 1000).takeIf { minutos > 0 },
            notaPassageiro = nota, textoBruto = ""
        )
    }
}

object Corridas {
    fun de(eventos: List<EventoLinha>): List<CorridaResumo> {
        val minutosPorOferta = HashMap<Int, Int>()
        for (e in eventos) if (e.tipo == TipoEvento.OFERTA_DETECTADA && e.oferta > 0 && e.minutos > 0) {
            minutosPorOferta[e.oferta] = e.minutos
        }
        val porId = LinkedHashMap<Int, CorridaResumo>()
        for (e in eventos.sortedWith(compareBy({ it.em }, { it.seq }))) {
            if (e.corrida <= 0) continue
            var c = porId[e.corrida] ?: CorridaResumo(e.corrida)
            when (e.tipo) {
                TipoEvento.ACEITE_DETECTADO -> {
                    c = c.copy(aceiteEm = e.em)
                    if (e.oferta > 0) {
                        c = c.copy(
                            valorOfertaCent = e.valorCent, buscaM = e.buscaM, viagemM = e.viagemM,
                            nota = if (e.nota100 > 0) e.nota100 / 100.0 else null,
                            minutos = minutosPorOferta[e.oferta] ?: 0
                        )
                    }
                }
                TipoEvento.PASSAGEIRO_A_BORDO -> c = c.copy(aBordoEm = e.em)
                TipoEvento.FIM_DETECTADO -> {
                    c = c.copy(fimEm = e.em)
                    if (e.motivo == Motivo.VALOR_FINAL_LIDO_NA_TELA && e.valorCent > 0) c = c.copy(valorFinalCent = e.valorCent)
                }
                TipoEvento.TRANSICAO -> {
                    val novo = e.estadoNovo
                    if (novo == EstadoCorrida.CONFIRMADA || novo == EstadoCorrida.ESTIMADA ||
                        novo == EstadoCorrida.INDETERMINADA || novo == EstadoCorrida.CANCELADA
                    ) {
                        c = c.copy(
                            encerradaEm = e.em,
                            confianca = e.confianca ?: Confianca.INDETERMINADO,
                            cancelada = novo == EstadoCorrida.CANCELADA
                        )
                    }
                }
                else -> {}
            }
            porId[e.corrida] = c
        }
        return porId.values.toList()
    }

    fun classificar(c: CorridaResumo, config: ConfigMoto): Veredito? =
        c.oferta()?.let { CalculadoraCorrida(config).analisar(it).veredito }
}

/** Totais de um conjunto de corridas e do tempo online correspondente. */
data class Resumo(val corridas: List<CorridaResumo>, val onlineMs: Long) {
    val confirmadas = corridas.filter { it.confirmada }
    val estimadas = corridas.filter { it.estimada }
    val faturado: Double = confirmadas.sumOf { it.valor ?: 0.0 }
    val estimado: Double = estimadas.sumOf { it.valor ?: 0.0 }

    /** Km pelas ofertas (busca + viagem) das corridas confirmadas. */
    val km: Double? = confirmadas.mapNotNull { it.km }.takeIf { it.isNotEmpty() }?.sum()

    val porHora: Double? get() = if (onlineMs >= 60_000) faturado / (onlineMs / 3_600_000.0) else null
    val porKm: Double? get() = km?.takeIf { it > 0 }?.let { faturado / it }
    val temDados get() = corridas.isNotEmpty() || onlineMs > 0

    fun lucro(config: ConfigMoto): Double? = km?.let { faturado - it * config.custoPorKm }
}

/** Junta corridas (da linha do tempo) e tempo online (dos turnos) por período. */
class Painel(val corridas: List<CorridaResumo>, val turnos: List<Turno>, val dias: List<Dia>) {
    private val zona = ZoneId.systemDefault()

    fun inicioDoDia(d: LocalDate) = d.atStartOfDay(zona).toInstant().toEpochMilli()

    fun resumo(de: LocalDate, ate: LocalDate, agora: Long = System.currentTimeMillis()): Resumo {
        val ini = inicioDoDia(de)
        val fim = inicioDoDia(ate.plusDays(1))
        val lista = corridas.filter { c -> c.termino?.let { it * 1000 in ini until fim } ?: false }
        var online = turnos.sumOf { it.onlineEntre(ini, fim, agora) }
        if (online == 0L) {
            // Dias de antes dos turnos existirem: tempo com a leitura ligada (relatório do dia)
            online = dias.filter { d ->
                val data = LocalDate.ofEpochDay(d.dia.toLong())
                !data.isBefore(de) && !data.isAfter(ate)
            }.sumOf { it.segundos * 1000L }
        }
        return Resumo(lista, online)
    }

    fun resumoTurno(t: Turno, agora: Long = System.currentTimeMillis()) =
        Resumo(corridas.filter { c -> c.termino?.let { t.contem(it * 1000) } ?: false }, t.onlineMs(agora))

    /** Dias que têm alguma corrida ou turno, do mais novo pro mais antigo. */
    fun diasComDados(): List<LocalDate> {
        val datas = corridas.mapNotNull { it.dia }.toMutableSet()
        turnos.forEach { datas.add(Instant.ofEpochMilli(it.inicio).atZone(zona).toLocalDate()) }
        return datas.sortedDescending()
    }
}
