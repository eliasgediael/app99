package com.elias.app99

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Equivalente da extensão de gravação do iOS: captura a tela (MediaProjection), lê o texto (ML Kit),
 * decide o estado das corridas (MotorCorrida) e avisa por notificação e voz.
 *
 * Só 1 frame a cada 0,5 s, e nenhum enquanto um OCR estiver rodando.
 */
class CapturaService : Service() {

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val ACAO_PARAR = "com.elias.app99.PARAR"
        const val ACAO_PAUSAR = "com.elias.app99.PAUSAR"
        const val ACAO_RETOMAR = "com.elias.app99.RETOMAR"
        private const val ID_NOTIFICACAO = 100
        private const val INTERVALO_MS = 500L
        private const val JANELA_REPETICAO_MS = 20_000L
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var threadCaptura: HandlerThread? = null

    // Tudo que mexe no motor e no diário roda nesta única thread
    private val filaOCR = Executors.newSingleThreadExecutor()
    private val ocrRodando = AtomicBoolean(false)
    @Volatile private var ultimoFrame = 0L
    @Volatile private var encerrando = false
    @Volatile private var pausado = false
    private var ultimoMarco = 0L

    private val reconhecedor = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private lateinit var diario: Diario
    private lateinit var motor: MotorCorrida
    private lateinit var narrador: Narrador
    private val avisadasEm = mutableMapOf<String, Long>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACAO_PARAR -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACAO_PAUSAR -> {
                if (projection != null) {
                    pausado = true
                    TurnoStore.get(this).pausar()
                    atualizarNotificacao()
                }
                return START_NOT_STICKY
            }
            ACAO_RETOMAR -> {
                if (projection != null) {
                    pausado = false
                    TurnoStore.get(this).retomar()
                    atualizarNotificacao()
                }
                return START_NOT_STICKY
            }
        }
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        }
        if (data == null || projection != null) {
            if (projection == null) stopSelf()
            return START_NOT_STICKY
        }

        Notificador.canais(this)
        val notificacao = montarNotificacao()
        if (Build.VERSION.SDK_INT >= 29) {
            // Com GPS permitido, o serviço também é de localização (km e mapa do turno)
            val tipo = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                (if (temGps()) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0)
            startForeground(ID_NOTIFICACAO, notificacao, tipo)
        } else {
            startForeground(ID_NOTIFICACAO, notificacao)
        }

        diario = Diario.get(this)
        motor = MotorCorrida(diario)
        narrador = Narrador(this)
        iniciarCaptura(code, data)
        return START_NOT_STICKY
    }

    private fun acao(acao: String, codigo: Int) = PendingIntent.getService(
        this, codigo, Intent(this, CapturaService::class.java).setAction(acao), PendingIntent.FLAG_IMMUTABLE
    )

    /** Notificação fixa do turno: ganhos de hoje e Pausar/Retomar, Abrir Apex, Encerrar. */
    private fun montarNotificacao(): Notification {
        val abrir = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val painel = Painel(Corridas.de(Diario.get(this).eventosFlow.value), TurnoStore.get(this).turnos.value, emptyList())
        val hoje = java.time.LocalDate.now()
        val r = painel.resumo(hoje, hoje)
        val texto = "Hoje ${Formato.reais(r.faturado)} · ${r.confirmadas.size} corridas" +
            (r.porHora?.let { " · ${Formato.reais(it)}/h" } ?: "")
        return NotificationCompat.Builder(this, Notificador.CANAL_SERVICO)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle(if (pausado) "Turno pausado" else "Turno ativo")
            .setContentText(texto)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(abrir)
            .addAction(0, if (pausado) "Retomar" else "Pausar", acao(if (pausado) ACAO_RETOMAR else ACAO_PAUSAR, 2))
            .addAction(0, "Abrir Apex", abrir)
            .addAction(0, "Encerrar", acao(ACAO_PARAR, 1))
            .build()
    }

    private fun atualizarNotificacao() {
        getSystemService(android.app.NotificationManager::class.java).notify(ID_NOTIFICACAO, montarNotificacao())
    }

    private fun iniciarCaptura(code: Int, data: Intent) {
        val thread = HandlerThread("apex-captura").also { it.start() }
        threadCaptura = thread
        val handler = Handler(thread.looper)

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = mpm.getMediaProjection(code, data)
        projection = proj
        // Android 14+: o callback tem que existir antes de criar o display virtual
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                if (!encerrando) stopSelf()
            }
        }, handler)

        val (largReal, altuReal, dpi) = medidasDaTela()
        val escala = min(1f, 1080f / min(largReal, altuReal))
        val larg = (largReal * escala).roundToInt()
        val altu = (altuReal * escala).roundToInt()

        val leitor = ImageReader.newInstance(larg, altu, PixelFormat.RGBA_8888, 2)
        reader = leitor
        leitor.setOnImageAvailableListener({ r -> aoChegarFrame(r) }, handler)
        virtualDisplay = proj.createVirtualDisplay(
            "apex", larg, altu, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            leitor.surface, null, handler
        )

        Estado.rodando.value = true
        val turno = TurnoStore.get(this).iniciar()
        Sobreposicao.ligar(this)
        ligarGps(turno, thread)
        filaOCR.execute {
            diario.comecarTempo()
            diario.adicionar(
                EventoLinha(em = System.currentTimeMillis() / 1000, tipo = TipoEvento.LEITURA_INICIADA,
                    origem = OrigemEvento.SISTEMA)
            )
            val c = Ajustes.config(this)
            Notificador.enviar(this, "Leitura ligada. Mínimo ${Formato.reais(c.minimoPorKm)}/km. Abra a 99.")
            if (Ajustes.vozLigada(this)) narrador.falar("Leitor da 99 ligado.", Ajustes.velocidade(this))
        }
    }

    // MARK: GPS do turno

    private var gps: android.location.LocationManager? = null

    private val ouvinteGps = object : android.location.LocationListener {
        override fun onLocationChanged(l: android.location.Location) {
            Rastro.adicionar(this@CapturaService, PontoGps(l.time, l.latitude, l.longitude, l.accuracy))
        }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Android antigo ainda chama")
        override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    }

    private fun temGps() = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun ligarGps(turno: Turno, thread: HandlerThread) {
        Rastro.comecar(this, turno.id)
        if (!temGps()) return
        val lm = getSystemService(android.location.LocationManager::class.java)
        try {
            lm.requestLocationUpdates(android.location.LocationManager.GPS_PROVIDER, 3_000L, 0f, ouvinteGps, thread.looper)
            gps = lm
        } catch (_: Exception) {
        }
    }

    private fun medidasDaTela(): Triple<Int, Int, Int> {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dpi = resources.displayMetrics.densityDpi
        return if (Build.VERSION.SDK_INT >= 30) {
            val b = wm.maximumWindowMetrics.bounds
            Triple(b.width(), b.height(), dpi)
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(m)
            Triple(m.widthPixels, m.heightPixels, dpi)
        }
    }

    // MARK: Frames

    private fun aoChegarFrame(r: ImageReader) {
        val img = try { r.acquireLatestImage() } catch (_: Exception) { null } ?: return
        val agora = SystemClock.elapsedRealtime()
        if (agora - ultimoFrame < INTERVALO_MS || !ocrRodando.compareAndSet(false, true)) {
            img.close()
            return
        }
        ultimoFrame = agora

        if (agora - ultimoMarco >= 60_000) {   // a cada minuto: turno vivo e notificação em dia
            ultimoMarco = agora
            TurnoStore.get(this).marcarVivo()
            atualizarNotificacao()
        }

        if (pausado || Estado.appNaFrente) {   // pausado, ou é a tela do próprio Apex: não ler
            img.close()
            filaOCR.execute {
                diario.acumularTempo()
                ocrRodando.set(false)
            }
            return
        }

        val bitmap = try { paraBitmap(img) } catch (_: Throwable) { null } finally { img.close() }
        if (bitmap == null) {
            ocrRodando.set(false)
            return
        }
        filaOCR.execute {
            try {
                analisar(bitmap)
            } catch (_: Throwable) {
            } finally {
                bitmap.recycle()
                ocrRodando.set(false)
            }
        }
    }

    /** Só os 65% de baixo da tela: o card da oferta fica ali e ignorar o mapa evita lixo no OCR. */
    private fun paraBitmap(img: Image): Bitmap {
        val plano = img.planes[0]
        val pixelStride = plano.pixelStride
        val larguraComBorda = plano.rowStride / pixelStride
        val cheio = Bitmap.createBitmap(larguraComBorda, img.height, Bitmap.Config.ARGB_8888)
        cheio.copyPixelsFromBuffer(plano.buffer)
        val y0 = (img.height * 0.35).toInt()
        val corte = Bitmap.createBitmap(cheio, 0, y0, img.width, img.height - y0)
        if (corte !== cheio) cheio.recycle()
        return corte
    }

    // MARK: Análise (filaOCR)

    private fun analisar(bitmap: Bitmap) {
        diario.acumularTempo()
        val texto = try {
            Tasks.await(reconhecedor.process(InputImage.fromBitmap(bitmap, 0)))
        } catch (_: Exception) {
            return
        }
        val linhas = ordenar(texto, bitmap.height)
        val agora = System.currentTimeMillis()

        val oferta = ParserOferta99.extrair(linhas)
        if (oferta != null && MotorCorrida.plausivel(oferta)) {
            val config = Ajustes.config(this)
            motor.custoPorKm = config.custoPorKm
            // Todo frame vai pro motor (ele precisa ver a oferta 2x pra valer)
            motor.observar(TelaLida.Oferta(oferta), agora)

            // Aviso imediato, sem esperar o motor: a oferta dura poucos segundos
            if (!ehNova(oferta, agora)) return
            val analise = CalculadoraCorrida(config).analisar(oferta)
            Estado.ultimaAnalise.value = analise
            Notificador.enviar(this, analise)
            Sobreposicao.mostrar(this, analise)
            if (Ajustes.vozLigada(this)) narrador.falar(analise.fraseFalada, Ajustes.velocidade(this))
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

    /** Linhas na ordem de leitura (cima → baixo, esquerda → direita). */
    private fun ordenar(texto: Text, altura: Int): List<String> {
        val tolerancia = maxOf(1f, altura * 0.01f)
        return texto.textBlocks.flatMap { it.lines }
            .filter { it.boundingBox != null }
            .sortedWith(
                compareBy<Text.Line>({ (it.boundingBox!!.exactCenterY() / tolerancia).roundToInt() },
                    { it.boundingBox!!.left })
            )
            .map { it.text }
    }

    /** Mesma oferta (valor + distâncias) só é avisada de novo depois de 20 s. */
    private fun ehNova(o: OfertaCorrida, agora: Long): Boolean {
        val chave = MotorCorrida.chave(o)
        avisadasEm.entries.removeAll { agora - it.value >= JANELA_REPETICAO_MS }
        if (avisadasEm.containsKey(chave)) return false
        avisadasEm[chave] = agora
        return true
    }

    // MARK: Encerramento

    override fun onDestroy() {
        encerrando = true
        gps?.removeUpdates(ouvinteGps)
        Rastro.parar(this)
        virtualDisplay?.release()
        reader?.close()
        try { projection?.stop() } catch (_: Exception) {}
        threadCaptura?.quitSafely()

        if (projection != null) {
            try {
                // Fecha as corridas abertas: viram ESTIMADA/INDETERMINADA, nunca CONFIRMADA
                filaOCR.submit(Runnable {
                    motor.encerrarTudo()
                    diario.adicionar(
                        EventoLinha(em = System.currentTimeMillis() / 1000, tipo = TipoEvento.LEITURA_ENCERRADA,
                            origem = OrigemEvento.SISTEMA)
                    )
                    diario.pararTempo()
                    val hoje = diario.hoje
                    if (hoje.corridas > 0 || hoje.ofertas > 0) Notificador.enviarResumo(this, hoje)
                }).get(5, TimeUnit.SECONDS)
            } catch (_: Exception) {
            }
            narrador.encerrar()
        }
        filaOCR.shutdown()
        Sobreposicao.desligar()
        TurnoStore.get(this).encerrar()
        Estado.rodando.value = false
        super.onDestroy()
    }
}
