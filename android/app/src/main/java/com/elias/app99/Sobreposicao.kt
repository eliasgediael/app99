package com.elias.app99

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PriorityHigh
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import java.time.LocalDate

/** O ComposeView precisa de um "dono" de ciclo de vida quando vive fora de uma Activity. */
private class DonoJanela : LifecycleOwner, SavedStateRegistryOwner {
    private val registro = LifecycleRegistry(this)
    private val controle = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = registro
    override val savedStateRegistry: SavedStateRegistry get() = controle.savedStateRegistry

    fun ligar() {
        controle.performRestore(null)
        registro.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        registro.handleLifecycleEvent(Lifecycle.Event.ON_START)
        registro.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
    }

    fun desligar() {
        registro.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
    }
}

/** Oferta mostrada no aviso. `teste` = exemplo disparado pelo usuário, não é oferta real. */
data class AvisoOferta(val analise: AnaliseCorrida, val teste: Boolean = false, val id: Long = System.nanoTime())

/**
 * Janelas do Apex por cima do 99Pop (permissão "Sobrepor a outros apps"):
 * bolha com os ganhos do dia, painel ao tocar nela e aviso colorido de cada oferta.
 * Todas com FLAG_SECURE: a gravação de tela do próprio Apex as vê pretas, então o OCR
 * nunca lê o aviso do Apex como se fosse uma oferta da 99.
 */
object Sobreposicao {
    private const val SEGUNDOS_AVISO = 8

    val aviso = MutableStateFlow<AvisoOferta?>(null)
    private val principal = Handler(Looper.getMainLooper())

    private var wm: WindowManager? = null
    private var bolhaView: ComposeView? = null
    private var bolhaParams: WindowManager.LayoutParams? = null
    private var avisoView: ComposeView? = null
    private val donos = mutableListOf<DonoJanela>()

    fun permitido(ctx: Context) = Settings.canDrawOverlays(ctx)

    /** Liga as janelas (chamado pelo serviço quando o turno começa). */
    fun ligar(ctx: Context) = principal.post {
        if (!permitido(ctx)) return@post
        val app = ctx.applicationContext
        val gerente = app.getSystemService(WindowManager::class.java)
        wm = gerente
        criarAviso(app, gerente)
        if (bolhaView == null && Ajustes.chave(app, "bolha", true)) {
            val dm = app.resources.displayMetrics
            val p = parametros(larguraCheia = false).apply {
                gravity = Gravity.TOP or Gravity.START
                x = dm.widthPixels - (96 * dm.density).toInt()
                y = (dm.heightPixels * 0.14).toInt()
            }
            bolhaParams = p
            bolhaView = criar(app) { Bolha(app) }.also { gerente.addView(it, p) }
        }
    }

    private fun criarAviso(app: Context, gerente: WindowManager) {
        if (avisoView != null) return
        val p = parametros(larguraCheia = true).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (16 * app.resources.displayMetrics.density).toInt()
        }
        avisoView = criar(app) { CartaoAviso() }.also { gerente.addView(it, p) }
    }

    fun desligar() = principal.post {
        listOfNotNull(bolhaView, avisoView).forEach { v -> try { wm?.removeView(v) } catch (_: Exception) {} }
        donos.forEach { it.desligar() }
        donos.clear()
        bolhaView = null
        avisoView = null
        aviso.value = null
    }

    /** Mostra o aviso de uma oferta (some sozinho em 8 s). */
    fun mostrar(ctx: Context, a: AnaliseCorrida) {
        if (!Ajustes.chave(ctx, "overlay", true)) return
        aviso.value = AvisoOferta(a)
    }

    /** Aviso de exemplo, pra ver como fica (marcado como teste). */
    fun testar(ctx: Context, v: Veredito) {
        if (!permitido(ctx)) return
        val oferta = when (v) {
            Veredito.BOA -> OfertaCorrida(12.10, 1.4, 9.8, 5, 23, 4.95, "")
            Veredito.ACEITAVEL -> OfertaCorrida(9.40, 1.2, 5.6, 4, 19, 4.80, "")
            Veredito.RUIM -> OfertaCorrida(5.20, 1.8, 2.9, 6, 13, 4.50, "")
        }
        val a = CalculadoraCorrida(Ajustes.config(ctx)).analisar(oferta)
        principal.post {
            val app = ctx.applicationContext
            val gerente = wm ?: app.getSystemService(WindowManager::class.java).also { wm = it }
            criarAviso(app, gerente)
            aviso.value = AvisoOferta(a, teste = true)
        }
    }

    private fun parametros(larguraCheia: Boolean) = WindowManager.LayoutParams(
        if (larguraCheia) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_SECURE,
        PixelFormat.TRANSLUCENT
    )

    private fun criar(ctx: Context, conteudo: @Composable () -> Unit): ComposeView {
        val dono = DonoJanela().also { it.ligar(); donos.add(it) }
        return ComposeView(ctx).apply {
            setViewTreeLifecycleOwner(dono)
            setViewTreeSavedStateRegistryOwner(dono)
            setContent { ApexTema(conteudo) }
        }
    }

    private fun moverBolha(dx: Float, dy: Float) {
        val p = bolhaParams ?: return
        val v = bolhaView ?: return
        p.x += dx.toInt()
        p.y += dy.toInt()
        try { wm?.updateViewLayout(v, p) } catch (_: Exception) {}
    }

    // MARK: Bolha e painel

    @Composable
    private fun Bolha(ctx: Context) {
        val naFrente by Estado.naFrente.collectAsState()
        val eventos by Diario.get(ctx).eventosFlow.collectAsState()
        val turnos by TurnoStore.get(ctx).turnos.collectAsState()
        var aberto by remember { mutableStateOf(false) }
        if (naFrente) return

        val hoje = LocalDate.now()
        val r = remember(eventos, turnos) {
            Painel(Corridas.de(eventos), turnos, emptyList()).resumo(hoje, hoje)
        }
        val turno = turnos.lastOrNull { it.ativo }

        if (!aberto) {
            Box(
                Modifier.size(84.dp).clip(CircleShape).background(Cor.fundo.copy(alpha = 0.94f))
                    .border(3.dp, Cor.verde, CircleShape)
                    .pointerInput(Unit) { detectDragGestures { m, d -> m.consume(); moverBolha(d.x, d.y) } }
                    .clickable { aberto = true },
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(Formato.reaisCurto(r.faturado), color = Cor.texto, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    Text("${r.confirmadas.size} corridas", color = Cor.texto2, fontSize = 10.sp)
                }
            }
        } else {
            Column(
                Modifier.width(280.dp).clip(RoundedCornerShape(20.dp)).background(Cor.fundo.copy(alpha = 0.97f))
                    .border(2.dp, Cor.verde, RoundedCornerShape(20.dp)).padding(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Hoje", color = Cor.texto2, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    Icon(Icons.Rounded.Close, "Fechar", tint = Cor.texto2,
                        modifier = Modifier.size(22.dp).clickable { aberto = false })
                }
                Text(Formato.reais(r.faturado), color = Cor.texto, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Text(r.porHora?.let { Formato.reais(it) + "/h" } ?: "— /h", color = Cor.texto2, modifier = Modifier.weight(1f))
                    Text(r.porKm?.let { Formato.reais(it) + "/km" } ?: "— /km", color = Cor.texto2)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val pausado = turno?.pausado == true
                    BotaoPainel(if (pausado) "Retomar" else "Pausar",
                        if (pausado) Icons.Rounded.PlayArrow else Icons.Rounded.Pause, Cor.cartaoAlto, Modifier.weight(1f)) {
                        comandoServico(ctx, if (pausado) CapturaService.ACAO_RETOMAR else CapturaService.ACAO_PAUSAR)
                    }
                    BotaoPainel("Abrir Apex", Icons.AutoMirrored.Rounded.OpenInNew, Cor.azul, Modifier.weight(1f)) {
                        aberto = false
                        ctx.startActivity(Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    BotaoPainel("Encerrar", Icons.Rounded.Stop, Cor.vermelho, Modifier.weight(1f)) {
                        comandoServico(ctx, CapturaService.ACAO_PARAR)
                    }
                }
            }
        }
    }

    @Composable
    private fun BotaoPainel(texto: String, icone: ImageVector, cor: Color, modifier: Modifier, aoTocar: () -> Unit) {
        Column(
            modifier.clip(RoundedCornerShape(12.dp)).background(cor).clickable(onClick = aoTocar)
                .padding(vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(icone, null, tint = Color.White, modifier = Modifier.size(20.dp))
            Text(texto, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
    }

    // MARK: Aviso de oferta

    @Composable
    private fun CartaoAviso() {
        val atual by aviso.collectAsState()
        val naFrente by Estado.naFrente.collectAsState()
        var restante by remember { mutableFloatStateOf(1f) }

        LaunchedEffect(atual?.id) {
            val a = atual ?: return@LaunchedEffect
            val passos = SEGUNDOS_AVISO * 10
            for (i in passos downTo 0) {
                restante = i / passos.toFloat()
                delay(100)
            }
            if (aviso.value?.id == a.id) aviso.value = null
        }

        AnimatedVisibility(
            visible = atual != null && (!naFrente || atual?.teste == true),
            enter = slideInVertically { -it } + fadeIn(),
            exit = slideOutVertically { -it } + fadeOut()
        ) {
            val a = atual ?: return@AnimatedVisibility
            val v = a.analise.veredito
            val o = a.analise.oferta
            Column(
                Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp))
                    .background(v.cor.copy(alpha = 0.92f).compositeOver(Cor.fundo))
                    .border(2.dp, v.cor, RoundedCornerShape(20.dp)).padding(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(28.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.9f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            when (v) {
                                Veredito.BOA -> Icons.Rounded.Check
                                Veredito.ACEITAVEL -> Icons.Rounded.PriorityHigh
                                Veredito.RUIM -> Icons.Rounded.Close
                            }, null, tint = v.cor, modifier = Modifier.size(20.dp)
                        )
                    }
                    Spacer(Modifier.width(10.dp))
                    Text(v.titulo + if (a.teste) " · TESTE" else "", color = Color.White, fontSize = 18.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Icon(Icons.Rounded.Close, "Fechar", tint = Color.White,
                        modifier = Modifier.size(24.dp).clickable { aviso.value = null })
                }
                Text(Formato.reais(o.valor), color = Color.White, fontSize = 38.sp, fontWeight = FontWeight.Bold)
                Row(verticalAlignment = Alignment.Bottom) {
                    Column(Modifier.weight(1f)) {
                        Text("Lucro", color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp)
                        Text(Formato.reais(a.analise.lucro), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                    Text("${Formato.reais(a.analise.ganhoPorKm)}/km", color = Color.White, fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Text(Formato.km(a.analise.kmTotal), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
                o.notaPassageiro?.let { n ->
                    Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Star, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(Formato.nota(n), color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Box(Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.3f))) {
                    Box(Modifier.fillMaxWidth(restante).height(5.dp).clip(RoundedCornerShape(50)).background(Color.White))
                }
                Text(
                    "Sumindo em ${Math.ceil(restante * SEGUNDOS_AVISO.toDouble()).toInt()} segundos",
                    color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}
