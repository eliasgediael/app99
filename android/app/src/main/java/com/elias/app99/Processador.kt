package com.elias.app99

import android.content.Context
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Recebe o texto da tela da 99 (pela acessibilidade ou pelo OCR da gravação) e faz o resto:
 * motor de corridas, aviso sobre o 99Pop, notificação e voz. Tudo numa thread só.
 */
object Processador {
    private const val JANELA_REPETICAO_MS = 20_000L

    private var fila: ExecutorService? = null
    private lateinit var app: Context
    private lateinit var diario: Diario
    private lateinit var motor: MotorCorrida
    private var narrador: Narrador? = null
    private val avisadasEm = HashMap<String, Long>()
    private val ocupado = AtomicBoolean(false)

    @Synchronized fun iniciar(ctx: Context) {
        if (fila != null) return
        app = ctx.applicationContext
        diario = Diario.get(app)
        motor = MotorCorrida(diario)
        narrador = Narrador(app)
        avisadasEm.clear()
        fila = Executors.newSingleThreadExecutor().also { f ->
            f.execute {
                diario.comecarTempo()
                diario.adicionar(
                    EventoLinha(em = System.currentTimeMillis() / 1000, tipo = TipoEvento.LEITURA_INICIADA,
                        origem = OrigemEvento.SISTEMA)
                )
                val c = Ajustes.config(app)
                Notificador.enviar(app, "Leitura ligada. Mínimo ${Formato.reais(c.minimoPorKm)}/km. Abra a 99.")
                if (Ajustes.vozLigada(app)) narrador?.falar("Leitor da 99 ligado.", Ajustes.velocidade(app))
            }
        }
    }

    /** Linhas da tela, na ordem de leitura. Se a anterior ainda está sendo analisada, esta é descartada. */
    fun processar(linhas: List<String>) {
        val f = fila ?: return
        if (!ocupado.compareAndSet(false, true)) return
        f.execute {
            try {
                analisar(linhas)
            } catch (_: Throwable) {
            } finally {
                ocupado.set(false)
            }
        }
    }

    /** Roda na mesma thread do motor (o OCR da gravação usa isto). */
    fun executar(bloco: () -> Unit) {
        fila?.execute(bloco)
    }

    /** Só pela thread do motor (dentro de `executar`). */
    fun analisarAgora(linhas: List<String>) = analisar(linhas)

    fun acumularTempo() {
        fila?.execute { diario.acumularTempo() }
    }

    /** Fecha as corridas abertas: viram ESTIMADA/INDETERMINADA, nunca CONFIRMADA. */
    @Synchronized fun encerrar() {
        val f = fila ?: return
        try {
            f.submit(Runnable {
                motor.encerrarTudo()
                diario.adicionar(
                    EventoLinha(em = System.currentTimeMillis() / 1000, tipo = TipoEvento.LEITURA_ENCERRADA,
                        origem = OrigemEvento.SISTEMA)
                )
                diario.pararTempo()
                val hoje = diario.hoje
                if (hoje.corridas > 0 || hoje.ofertas > 0) Notificador.enviarResumo(app, hoje)
            }).get(5, TimeUnit.SECONDS)
        } catch (_: Exception) {
        }
        narrador?.encerrar()
        narrador = null
        f.shutdown()
        fila = null
    }

    private fun analisar(linhas: List<String>) {
        diario.acumularTempo()
        if (linhas.isEmpty()) return
        val agora = System.currentTimeMillis()

        val oferta = ParserOferta99.extrair(linhas)
        if (oferta != null && MotorCorrida.plausivel(oferta)) {
            val config = Ajustes.config(app)
            motor.custoPorKm = config.custoPorKm
            // Toda leitura vai pro motor (ele precisa ver a oferta 2x pra valer)
            motor.observar(TelaLida.Oferta(oferta), agora)

            // Aviso imediato, sem esperar o motor: a oferta dura poucos segundos
            if (!ehNova(oferta, agora)) return
            val analise = CalculadoraCorrida(config).analisar(oferta)
            Estado.ultimaAnalise.value = analise
            Notificador.enviar(app, analise)
            Sobreposicao.mostrar(app, analise)
            if (Ajustes.vozLigada(app)) narrador?.falar(analise.fraseFalada, Ajustes.velocidade(app))
            return
        }

        val tela = when (TelaCorrida.identificar(linhas)) {
            TelaCorrida.A_CAMINHO -> TelaLida.ACaminho
            TelaCorrida.EMBARQUE -> TelaLida.Embarque
            TelaCorrida.A_BORDO -> TelaLida.ABordo
            TelaCorrida.FIM -> TelaLida.Fim(ParserOferta99.maiorValorCent(linhas))
            TelaCorrida.CANCELADA -> TelaLida.Cancelada
            TelaCorrida.OUTRA -> TelaLida.Outra
        }
        motor.observar(tela, agora)
    }

    /** Mesma oferta (valor + distâncias) só é avisada de novo depois de 20 s. */
    private fun ehNova(o: OfertaCorrida, agora: Long): Boolean {
        val chave = MotorCorrida.chave(o)
        avisadasEm.entries.removeAll { agora - it.value >= JANELA_REPETICAO_MS }
        if (avisadasEm.containsKey(chave)) return false
        avisadasEm[chave] = agora
        return true
    }
}
