package com.elias.app99

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Lê o texto da tela da 99 pela acessibilidade (sem gravar a tela e sem OCR).
 * Só durante o turno, só apps da 99, e só lê: não toca em nada (não aceita nem recusa corrida).
 */
class LeituraAcessibilidade : AccessibilityService() {

    private var ultimaLeitura = 0L

    override fun onAccessibilityEvent(evento: AccessibilityEvent?) {
        if (!Estado.rodando.value || Estado.pausado || Estado.appNaFrente) return
        if (Ajustes.modoLeitura(this) != MODO_ACESSIBILIDADE) return
        val pacote = evento?.packageName?.toString() ?: return
        if (!eh99(pacote)) return
        val agora = SystemClock.elapsedRealtime()
        if (agora - ultimaLeitura < INTERVALO_MS) return
        ultimaLeitura = agora

        val linhas = mutableListOf<Pedaco>()
        val janelas = try { windows } catch (_: Exception) { emptyList() }
        var achou = false
        for (j in janelas) {
            val raiz = j.root ?: continue
            if (eh99(raiz.packageName?.toString() ?: "")) {
                coletar(raiz, linhas)
                achou = true
            }
        }
        if (!achou) rootInActiveWindow?.let { r -> if (eh99(r.packageName?.toString() ?: "")) coletar(r, linhas) }

        Estado.pacoteLido.value = pacote
        Processador.processar(ordenar(linhas))
    }

    override fun onInterrupt() {}

    private data class Pedaco(val texto: String, val topo: Int, val centroY: Int, val esquerda: Int)

    private fun coletar(no: AccessibilityNodeInfo, saida: MutableList<Pedaco>, profundidade: Int = 0) {
        if (profundidade > 40) return
        if (no.isVisibleToUser) {
            val texto = (no.text ?: no.contentDescription)?.toString()?.trim()
            if (!texto.isNullOrEmpty()) {
                val r = Rect()
                no.getBoundsInScreen(r)
                texto.split('\n').map { it.trim() }.filter { it.isNotEmpty() }.forEachIndexed { i, parte ->
                    saida.add(Pedaco(parte, r.top, r.centerY() + i, r.left))
                }
            }
        }
        for (i in 0 until no.childCount) {
            val filho = no.getChild(i) ?: continue
            coletar(filho, saida, profundidade + 1)
            if (Build.VERSION.SDK_INT < 33) {
                @Suppress("DEPRECATION") filho.recycle()
            }
        }
    }

    /** Ordem de leitura (cima → baixo, esquerda → direita), igual ao OCR. */
    private fun ordenar(pedacos: List<Pedaco>): List<String> {
        val faixa = (resources.displayMetrics.heightPixels * 0.01f).toInt().coerceAtLeast(1)
        return pedacos.distinct()
            .sortedWith(compareBy<Pedaco>({ it.centroY / faixa }, { it.esquerda }))
            .map { it.texto }
    }

    companion object {
        const val MODO_ACESSIBILIDADE = "acessibilidade"
        const val MODO_GRAVACAO = "gravacao"
        private const val INTERVALO_MS = 400L

        /** Apps da 99 (motorista). O próprio Apex nunca é lido. */
        fun eh99(pacote: String): Boolean =
            pacote != "com.elias.app99" && (pacote.contains("99") || pacote.contains("didi", ignoreCase = true))

        /** O usuário ligou o Apex em Ajustes → Acessibilidade? */
        fun ativa(ctx: Context): Boolean {
            val lista = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?: return false
            val nosso = ComponentName(ctx, LeituraAcessibilidade::class.java)
            return lista.split(':').any { ComponentName.unflattenFromString(it) == nosso }
        }
    }
}
