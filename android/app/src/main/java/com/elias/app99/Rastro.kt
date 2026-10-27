package com.elias.app99

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

data class PontoGps(val t: Long, val lat: Double, val lon: Double, val precisao: Float)

/**
 * GPS do turno: liga só com o turno. Pontos ruins (precisão > 50 m), tremida parado e saltos
 * impossíveis ficam de fora; trechos sem sinal (> 2 min) não são ligados em linha reta.
 * Cada turno grava em gps-<id>.json.
 */
object Rastro {
    private const val PRECISAO_MAX = 50f
    private const val BURACO_MS = 120_000L
    private const val VELOCIDADE_MAX = 150 / 3.6   // m/s

    /** Última posição boa (marca onde cada evento da leitura aconteceu). */
    @Volatile var ultima: PontoGps? = null
        private set

    private val pontos = mutableListOf<PontoGps>()
    private var turnoId: String? = null
    private var salvoEm = 0L
    private val cache = HashMap<String, List<PontoGps>>()

    private fun arquivo(ctx: Context, id: String) = File(ctx.filesDir, "gps-$id.json")

    @Synchronized fun comecar(ctx: Context, id: String) {
        if (turnoId == id) return
        turnoId = id
        pontos.clear()
        pontos.addAll(ler(ctx, id))
    }

    @Synchronized fun adicionar(ctx: Context, p: PontoGps) {
        if (p.precisao > PRECISAO_MAX) return
        ultima = p
        val u = pontos.lastOrNull()
        if (u != null && (p.t <= u.t || (p.t - u.t < 15_000 && metros(u, p) < 10))) return
        pontos.add(p)
        if (p.t - salvoEm > 60_000) salvar(ctx)
    }

    @Synchronized fun parar(ctx: Context) {
        salvar(ctx)
        turnoId?.let { cache[it] = pontos.toList() }
        turnoId = null
        pontos.clear()
        ultima = null
    }

    @Synchronized private fun salvar(ctx: Context) {
        val id = turnoId ?: return
        salvoEm = System.currentTimeMillis()
        val arr = JSONArray(pontos.map {
            JSONObject().put("t", it.t).put("a", it.lat).put("o", it.lon).put("p", it.precisao.toDouble())
        })
        try { arquivo(ctx, id).writeText(arr.toString()) } catch (_: Exception) {}
    }

    /** Pontos de um turno (o atual vem da memória). */
    @Synchronized fun de(ctx: Context, t: Turno): List<PontoGps> {
        if (t.id == turnoId) return pontos.toList()
        return cache.getOrPut(t.id) { ler(ctx, t.id) }
    }

    private fun ler(ctx: Context, id: String): List<PontoGps> = try {
        val f = arquivo(ctx, id)
        if (!f.exists()) emptyList() else {
            val arr = JSONArray(f.readText())
            (0 until arr.length()).map {
                val j = arr.getJSONObject(it)
                PontoGps(j.getLong("t"), j.getDouble("a"), j.getDouble("o"), j.optDouble("p", 10.0).toFloat())
            }
        }
    } catch (_: Exception) {
        emptyList()
    }

    /** Km rodados entre [de, ate), com os filtros acima. */
    fun km(pontos: List<PontoGps>, de: Long, ate: Long): Double {
        var total = 0.0
        var anterior: PontoGps? = null
        for (p in pontos) {
            if (p.t < de || p.t >= ate) continue
            val a = anterior
            anterior = p
            if (a == null || p.t - a.t > BURACO_MS) continue
            val d = metros(a, p)
            val dt = (p.t - a.t) / 1000.0
            if (dt <= 0 || d / dt > VELOCIDADE_MAX) continue
            total += d
        }
        return total / 1000
    }

    fun metros(a: PontoGps, b: PontoGps) = metros(a.lat, a.lon, b.lat, b.lon)

    fun metros(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }
}
