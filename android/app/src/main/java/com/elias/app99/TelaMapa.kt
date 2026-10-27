package com.elias.app99

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Point
import android.graphics.RadialGradient
import android.graphics.Shader
import android.location.Geocoder
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Overlay
import org.osmdroid.views.overlay.TilesOverlay
import java.time.LocalDate
import java.util.Locale
import kotlin.math.floor
import kotlin.random.Random

/** Um ponto de ganho: onde o passageiro embarcou e quanto a corrida pagou. */
data class PontoGanho(val lat: Double, val lon: Double, val valor: Double)

/** Mancha de calor: cada embarque vira um círculo; a cor vai do azul (pouco) ao vermelho (muito). */
private class CamadaCalor(var pontos: List<PontoGanho>) : Overlay() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val p = Point()

    override fun draw(c: Canvas, mapa: MapView, sombra: Boolean) {
        if (sombra || pontos.isEmpty()) return
        val maior = pontos.maxOf { it.valor }.coerceAtLeast(1.0)
        val raio = (40 * mapa.context.resources.displayMetrics.density) * (mapa.zoomLevelDouble / 13.0).toFloat()
        for (g in pontos) {
            mapa.projection.toPixels(GeoPoint(g.lat, g.lon), p)
            val cor = corCalor(g.valor / maior)
            paint.shader = RadialGradient(
                p.x.toFloat(), p.y.toFloat(), raio.coerceAtLeast(12f),
                intArrayOf(comAlfa(cor, 150), comAlfa(cor, 0)), null, Shader.TileMode.CLAMP
            )
            c.drawCircle(p.x.toFloat(), p.y.toFloat(), raio.coerceAtLeast(12f), paint)
        }
    }

    private fun comAlfa(cor: Int, a: Int) = (cor and 0x00FFFFFF) or (a shl 24)
}

/** 0 = azul, 0,5 = verde/amarelo, 1 = vermelho. */
private fun corCalor(f: Double): Int {
    val paradas = listOf(0xFF3B82F6.toInt(), 0xFF10B981.toInt(), 0xFFF5B83D.toInt(), 0xFFEF4444.toInt())
    val x = f.coerceIn(0.0, 1.0) * (paradas.size - 1)
    val i = floor(x).toInt().coerceAtMost(paradas.size - 2)
    val t = x - i
    val a = paradas[i]
    val b = paradas[i + 1]
    fun canal(s: Int) = (((a shr s) and 0xFF) + (((b shr s) and 0xFF) - ((a shr s) and 0xFF)) * t).toInt()
    return (0xFF shl 24) or (canal(16) shl 16) or (canal(8) shl 8) or canal(0)
}

/** Região de ~1 km onde houve embarques. */
data class Area(val chave: String, val lat: Double, val lon: Double, val corridas: Int, val valor: Double, val km: Double) {
    val porKm: Double? get() = if (km > 0) valor / km else null
}

private fun areas(pontos: List<Pair<PontoGanho, Double?>>): List<Area> =
    pontos.groupBy { (g, _) -> "${floor(g.lat / 0.01).toInt()}:${floor(g.lon / 0.01).toInt()}" }
        .map { (chave, lista) ->
            Area(
                chave, lista.map { it.first.lat }.average(), lista.map { it.first.lon }.average(),
                lista.size, lista.sumOf { it.first.valor }, lista.sumOf { it.second ?: 0.0 }
            )
        }
        .sortedByDescending { it.valor }

@Composable
fun TelaMapa(abrir: (Detalhe) -> Unit) {
    val ctx = LocalContext.current
    val painel = lembrarPainel()
    var aba by rememberSaveable { mutableIntStateOf(0) }
    var exemplo by remember { mutableStateOf(false) }

    // Últimos 30 dias: corridas confirmadas com GPS no embarque
    val inicio = LocalDate.now().minusDays(29)
    val reais = remember(painel) {
        painel.corridas.filter { c ->
            c.confirmada && c.embarque != null && c.dia?.let { !it.isBefore(inicio) } == true
        }.map { c -> PontoGanho(c.embarque!!.first, c.embarque.second, c.valor ?: 0.0) to c.km }
    }
    val centroReal = reais.firstOrNull()?.first?.let { GeoPoint(it.lat, it.lon) }
        ?: Rastro.ultima?.let { GeoPoint(it.lat, it.lon) }
    val demo = remember(exemplo, centroReal) {
        if (!exemplo) emptyList() else {
            val c = centroReal ?: GeoPoint(-20.4697, -54.6201)
            val r = Random(7)
            (0 until 40).map {
                PontoGanho(c.latitude + r.nextDouble(-0.03, 0.03), c.longitude + r.nextDouble(-0.03, 0.03),
                    r.nextDouble(5.0, 25.0)) to r.nextDouble(2.0, 12.0)
            }
        }
    }
    val pontos = if (reais.isEmpty()) demo else reais

    Column(Modifier.fillMaxSize()) {
        BarraTopo("Mapa", null)
        Column(Modifier.padding(horizontal = 18.dp)) {
            Segmentos(listOf(0, 1), { if (it == 0) "Mapa de ganhos" else "Áreas" }, aba) { aba = it }
            if (reais.isEmpty() && exemplo) {
                Spacer(Modifier.height(8.dp))
                SeloDemonstracao()
            }
        }
        Spacer(Modifier.height(10.dp))
        if (aba == 0) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                MapaCalor(pontos.map { it.first }, centroReal)
                if (pontos.isEmpty()) {
                    Column(
                        Modifier.align(Alignment.Center).clip(RoundedCornerShape(16.dp)).background(Cor.cartao)
                            .padding(18.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Sem corridas com GPS ainda", color = Cor.texto, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(8.dp))
                        Text("Ver exemplo", color = Cor.azul, fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.clickable { exemplo = true })
                    }
                }
                LegendaCalor(Modifier.align(Alignment.BottomCenter).padding(14.dp))
            }
        } else {
            ListaAreas(ctx, areas(pontos), reais.isEmpty() && exemplo)
        }
    }
}

@Composable
private fun MapaCalor(pontos: List<PontoGanho>, centro: GeoPoint?) {
    val camada = remember { CamadaCalor(emptyList()) }
    var centrado by remember { mutableStateOf(false) }
    var mapaRef by remember { mutableStateOf<MapView?>(null) }
    Box(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { c ->
                Configuration.getInstance().userAgentValue = c.packageName
                MapView(c).apply {
                    setTileSource(TileSourceFactory.MAPNIK)
                    setMultiTouchControls(true)
                    zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
                    overlayManager.tilesOverlay.setColorFilter(TilesOverlay.INVERT_COLORS)
                    controller.setZoom(13.0)
                    controller.setCenter(GeoPoint(-15.78, -47.93))
                    overlays.add(camada)
                    mapaRef = this
                }
            },
            update = { mapa ->
                camada.pontos = pontos
                // Enquadra só na primeira vez: depois, o zoom do usuário fica
                val alvo = centro ?: pontos.firstOrNull()?.let { GeoPoint(it.lat, it.lon) }
                if (!centrado && alvo != null) {
                    mapa.controller.setCenter(alvo)
                    centrado = true
                }
                mapa.invalidate()
            }
        )
        Box(
            Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 90.dp).size(48.dp).clip(CircleShape)
                .background(Cor.cartao).clickable {
                    val u = Rastro.ultima
                    val alvo = u?.let { GeoPoint(it.lat, it.lon) } ?: centro
                    if (alvo != null) mapaRef?.controller?.animateTo(alvo)
                },
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Rounded.MyLocation, "Minha posição", tint = Cor.texto) }
    }
}

@Composable
private fun LegendaCalor(modifier: Modifier) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Cor.cartao.copy(alpha = 0.95f)).padding(14.dp)
    ) {
        Text("Ganhos na região", color = Cor.texto, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        Box(
            Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50))
                .background(Brush.horizontalGradient(listOf(Cor.azul, Cor.verde, Cor.ambar, Cor.vermelho)))
        )
        Spacer(Modifier.height(4.dp))
        Row(Modifier.fillMaxWidth()) {
            Text("Baixo", color = Cor.texto2, fontSize = 12.sp, modifier = Modifier.weight(1f))
            Text("Alto", color = Cor.texto2, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ListaAreas(ctx: Context, lista: List<Area>, exemplo: Boolean) {
    val nomes = remember { mutableStateMapOf<String, String>() }
    val usarNomes = Ajustes.chave(ctx, "bairros", false) && !exemplo
    LaunchedEffect(lista, usarNomes) {
        if (!usarNomes) return@LaunchedEffect
        for (a in lista.take(10)) {
            if (nomes.containsKey(a.chave)) continue
            val nome = withContext(Dispatchers.IO) { nomeDaArea(ctx, a) }
            if (nome != null) nomes[a.chave] = nome
        }
    }
    if (lista.isEmpty()) {
        EstadoVazio("Sem corridas com GPS ainda")
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        itemsIndexed(lista.take(20)) { i, a ->
            val fracao = a.valor / (lista.first().valor.takeIf { it > 0 } ?: 1.0)
            Cartao(espaco = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).clip(CircleShape).background(Color(corCalor(fracao))))
                    Spacer(Modifier.size(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(nomes[a.chave] ?: "Área ${i + 1}", color = Cor.texto, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${a.corridas} corrida${if (a.corridas == 1) "" else "s"}" +
                                (a.porKm?.let { " · ${Formato.reais(it)}/km" } ?: ""),
                            color = Cor.texto2, fontSize = 13.sp
                        )
                    }
                    Text(Formato.reais(a.valor), color = Cor.texto, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

/** Nome do bairro pelo serviço de mapas do aparelho (só com "Identificar bairros" ligado). */
@Suppress("DEPRECATION")
private fun nomeDaArea(ctx: Context, a: Area): String? = try {
    Geocoder(ctx, Locale("pt", "BR")).getFromLocation(a.lat, a.lon, 1)?.firstOrNull()
        ?.let { it.subLocality ?: it.locality }
} catch (_: Exception) {
    null
}
