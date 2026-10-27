package com.elias.app99

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Pausa(val inicio: Long, val fim: Long? = null)

/** Uma sessão de trabalho, do "Iniciar turno" ao "Encerrar". Tempos em milissegundos. */
data class Turno(
    val id: String,
    val inicio: Long,
    val fim: Long? = null,
    val pausas: List<Pausa> = emptyList()
) {
    val ativo get() = fim == null
    val pausado get() = pausas.lastOrNull()?.let { it.fim == null } ?: false

    fun contem(ms: Long) = ms >= inicio && ms <= (fim ?: Long.MAX_VALUE)
    fun duracaoMs(agora: Long = System.currentTimeMillis()) = (fim ?: agora) - inicio
    fun pausadoMs(agora: Long = System.currentTimeMillis()) =
        pausas.sumOf { ((it.fim ?: fim ?: agora) - it.inicio).coerceAtLeast(0) }

    /** Tempo online = turno menos pausas. */
    fun onlineMs(agora: Long = System.currentTimeMillis()) = (duracaoMs(agora) - pausadoMs(agora)).coerceAtLeast(0)

    /** Parte do tempo online dentro de [de, ate). */
    fun onlineEntre(de: Long, ate: Long, agora: Long = System.currentTimeMillis()): Long {
        val ini = maxOf(inicio, de)
        val fimT = minOf(fim ?: agora, ate)
        if (fimT <= ini) return 0
        var total = fimT - ini
        for (p in pausas) {
            val pi = maxOf(p.inicio, ini)
            val pf = minOf(p.fim ?: fimT, fimT)
            if (pf > pi) total -= (pf - pi)
        }
        return total.coerceAtLeast(0)
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("inicio", inicio); put("fim", fim ?: 0L)
        put("pausas", JSONArray(pausas.map { JSONObject().put("i", it.inicio).put("f", it.fim ?: 0L) }))
    }

    companion object {
        fun deJson(j: JSONObject): Turno {
            val arr = j.optJSONArray("pausas") ?: JSONArray()
            val pausas = (0 until arr.length()).map {
                val p = arr.getJSONObject(it)
                Pausa(p.optLong("i"), p.optLong("f").takeIf { f -> f > 0 })
            }
            return Turno(j.getString("id"), j.optLong("inicio"), j.optLong("fim").takeIf { it > 0 }, pausas)
        }
    }
}

/** Turnos salvos no aparelho. O serviço de leitura abre e fecha; as telas só leem. */
class TurnoStore private constructor(ctx: Context) {
    private val prefs = ctx.getSharedPreferences("turnos", Context.MODE_PRIVATE)
    private val _turnos = MutableStateFlow<List<Turno>>(emptyList())
    val turnos: StateFlow<List<Turno>> = _turnos

    companion object {
        @Volatile private var inst: TurnoStore? = null
        fun get(ctx: Context): TurnoStore =
            inst ?: synchronized(this) { inst ?: TurnoStore(ctx.applicationContext).also { inst = it } }
    }

    init {
        _turnos.value = try {
            val arr = JSONArray(prefs.getString("lista", "[]"))
            (0 until arr.length()).map { Turno.deJson(arr.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
        // Turno que ficou aberto quando o app foi fechado à força: encerra onde parou de ter sinal
        val aberto = _turnos.value.lastOrNull { it.ativo }
        if (aberto != null && !Estado.rodando.value) fecharAberto(aberto)
    }

    val atual: Turno? get() = _turnos.value.lastOrNull { it.ativo }

    @Synchronized fun iniciar(agora: Long = System.currentTimeMillis()): Turno {
        atual?.let { return it }
        val t = Turno(UUID.randomUUID().toString(), agora)
        salvar(_turnos.value + t)
        return t
    }

    @Synchronized fun encerrar(agora: Long = System.currentTimeMillis()) {
        val t = atual ?: return
        val pausas = if (t.pausado) t.pausas.dropLast(1) + t.pausas.last().copy(fim = agora) else t.pausas
        trocar(t, t.copy(fim = agora, pausas = pausas))
    }

    @Synchronized fun pausar(agora: Long = System.currentTimeMillis()) {
        val t = atual ?: return
        if (t.pausado) return
        trocar(t, t.copy(pausas = t.pausas + Pausa(agora)))
    }

    @Synchronized fun retomar(agora: Long = System.currentTimeMillis()) {
        val t = atual ?: return
        if (!t.pausado) return
        trocar(t, t.copy(pausas = t.pausas.dropLast(1) + t.pausas.last().copy(fim = agora)))
    }

    private fun fecharAberto(t: Turno) {
        val ultimoMarco = prefs.getLong("marco", t.inicio).coerceAtLeast(t.inicio)
        val pausas = if (t.pausado) t.pausas.dropLast(1) + t.pausas.last().copy(fim = ultimoMarco) else t.pausas
        trocar(t, t.copy(fim = ultimoMarco, pausas = pausas))
    }

    /** O serviço marca "ainda vivo" de tempos em tempos: se o Android matar o app, o turno fecha ali. */
    fun marcarVivo(agora: Long = System.currentTimeMillis()) {
        prefs.edit().putLong("marco", agora).apply()
    }

    private fun trocar(velho: Turno, novo: Turno) {
        salvar(_turnos.value.map { if (it.id == velho.id) novo else it })
    }

    private fun salvar(lista: List<Turno>) {
        _turnos.value = lista
        prefs.edit().putString("lista", JSONArray(lista.map { it.toJson() }).toString()).apply()
    }
}
