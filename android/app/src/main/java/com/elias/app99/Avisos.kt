package com.elias.app99

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale

/** Notificação local — garante o aviso mesmo se a voz estiver desligada. */
object Notificador {
    const val CANAL_AVISO = "ofertas"
    const val CANAL_SERVICO = "servico"

    fun canais(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CANAL_AVISO, "Avisos de corrida", NotificationManager.IMPORTANCE_HIGH)
        )
        nm.createNotificationChannel(
            NotificationChannel(CANAL_SERVICO, "Leitura ativa", NotificationManager.IMPORTANCE_LOW)
        )
    }

    /** 🟢 Corrida boa · ⭐ 4,95 / 💵 R$ 12,10 · 💰 Lucro R$ 8,18 / 📊 R$ 1,08/km · 📏 11,2 km */
    fun enviar(ctx: Context, a: AnaliseCorrida) {
        if (!Ajustes.chave(ctx, "notificacoes", true)) return
        var titulo = "${a.veredito.emoji} ${a.veredito.falado}"
        a.oferta.notaPassageiro?.let {
            titulo += " · ⭐ ${Formato.nota(it)}"
            if (a.notaBaixa) titulo += " nota baixa"
        }
        // Recolhida a notificação mostra só uma linha: tudo vai nela
        enviar(
            ctx, titulo,
            "💵 ${Formato.reais(a.oferta.valor)} · 💰 ${Formato.reais(a.lucro)} · " +
                "📊 ${Formato.reais(a.ganhoPorKm)}/km · 📏 ${Formato.km(a.kmTotal)}",
            1
        )
    }

    fun enviar(ctx: Context, frase: String) = enviar(ctx, "Apex", frase, 3)

    fun enviarResumo(ctx: Context, d: Dia) {
        enviar(
            ctx, "📋 Resumo de hoje",
            "💵 ${Formato.reais(d.faturado)} · 💰 Lucro ${Formato.reais(d.lucro)}\n" +
                "🛵 ${d.corridas} corrida${if (d.corridas == 1) "" else "s"} · ${Formato.km(d.km)} · " +
                "✅ ${d.corridas} de ${d.ofertas} ofertas",
            2
        )
    }

    // Id fixo: oferta nova substitui a anterior em vez de empilhar
    private fun enviar(ctx: Context, titulo: String, corpo: String, id: Int) {
        canais(ctx)
        val n = NotificationCompat.Builder(ctx, CANAL_AVISO)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(titulo)
            .setContentText(corpo.replace("\n", " · "))
            .setStyle(NotificationCompat.BigTextStyle().bigText(corpo))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        // Sem permissão de notificação (Android 13+), o sistema só ignora
        ctx.getSystemService(NotificationManager::class.java).notify(id, n)
    }
}

/** Fala o resultado em pt-BR por cima do app da 99 (o sistema abaixa o volume da música). */
class Narrador(ctx: Context) {
    private var pronto = false
    private val tts: TextToSpeech = TextToSpeech(ctx.applicationContext) { status ->
        pronto = status == TextToSpeech.SUCCESS
    }

    init {
        tts.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
    }

    fun falar(texto: String, velocidade: Float) {
        if (!pronto) return
        tts.language = Locale("pt", "BR")
        tts.setSpeechRate(velocidade)
        tts.speak(texto, TextToSpeech.QUEUE_FLUSH, null, "oferta")
    }

    fun encerrar() {
        tts.stop()
        tts.shutdown()
    }
}
