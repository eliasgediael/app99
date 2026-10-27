package com.elias.app99

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.time.LocalDate
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Serviço do turno: notificação fixa, GPS, bolha/aviso sobre o 99Pop.
 * A leitura da 99 vem da acessibilidade (padrão, ver LeituraAcessibilidade) ou, como reserva,
 * da gravação de tela + OCR (MediaProjection + ML Kit) feita aqui.
 */
class CapturaService : Service() {

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val ACAO_INICIAR = "com.elias.app99.INICIAR"   // turno lendo pela acessibilidade
        const val ACAO_PARAR = "com.elias.app99.PARAR"
        const val ACAO_PAUSAR = "com.elias.app99.PAUSAR"
        const val ACAO_RETOMAR = "com.elias.app99.RETOMAR"
        private const val ID_NOTIFICACAO = 100
        private const val INTERVALO_MS = 500L
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var ativo = false

    private val ocrRodando = AtomicBoolean(false)
    @Volatile private var ultimoFrame = 0L
    @Volatile private var encerrando = false
    private val reconhecedor by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACAO_PARAR -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACAO_PAUSAR -> {
                if (ativo) {
                    Estado.pausado = true
                    TurnoStore.get(this).pausar()
                    atualizarNotificacao()
                }
                return START_NOT_STICKY
            }
            ACAO_RETOMAR -> {
                if (ativo) {
                    Estado.pausado = false
                    TurnoStore.get(this).retomar()
                    atualizarNotificacao()
                }
                return START_NOT_STICKY
            }
            ACAO_INICIAR -> {
                if (!ativo) comecarTurno(gravacao = false)
                return START_NOT_STICKY
            }
        }

        // Reserva: gravação de tela (o usuário aceitou o pedido do Android)
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        }
        if (data == null || ativo) {
            if (!ativo) stopSelf()
            return START_NOT_STICKY
        }
        comecarTurno(gravacao = true)
        iniciarGravacao(code, data)
        return START_NOT_STICKY
    }

    private fun comecarTurno(gravacao: Boolean) {
        ativo = true
        Estado.pausado = false
        Notificador.canais(this)
        val notificacao = montarNotificacao()
        if (Build.VERSION.SDK_INT >= 29) {
            var tipo = if (temGps()) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
            if (gravacao) tipo = tipo or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            if (Build.VERSION.SDK_INT >= 34 && tipo == 0) tipo = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            startForeground(ID_NOTIFICACAO, notificacao, tipo)
        } else {
            startForeground(ID_NOTIFICACAO, notificacao)
        }

        val t = HandlerThread("apex-turno").also { it.start() }
        thread = t
        val h = Handler(t.looper)
        handler = h

        Estado.rodando.value = true
        val turno = TurnoStore.get(this).iniciar()
        Processador.iniciar(this)
        Sobreposicao.ligar(this)
        ligarGps(turno, t)
        h.postDelayed(object : Runnable {
            override fun run() {   // a cada minuto: turno vivo, tempo online e notificação em dia
                if (!ativo) return
                TurnoStore.get(this@CapturaService).marcarVivo()
                if (!Estado.pausado) Processador.acumularTempo()
                atualizarNotificacao()
                h.postDelayed(this, 60_000)
            }
        }, 60_000)
    }

    // MARK: Notificação

    private fun acao(acao: String, codigo: Int) = PendingIntent.getService(
        this, codigo, Intent(this, CapturaService::class.java).setAction(acao), PendingIntent.FLAG_IMMUTABLE
    )

    /** Notificação fixa do turno: ganhos de hoje e Pausar/Retomar, Abrir Apex, Encerrar. */
    private fun montarNotificacao(): Notification {
        val abrir = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val painel = Painel(Corridas.de(Diario.get(this).eventosFlow.value), TurnoStore.get(this).turnos.value, emptyList())
        val hoje = LocalDate.now()
        val r = painel.resumo(hoje, hoje)
        val texto = "Hoje ${Formato.reais(r.faturado)} · ${r.confirmadas.size} corridas" +
            (r.porHora?.let { " · ${Formato.reais(it)}/h" } ?: "")
        val pausado = Estado.pausado
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
        getSystemService(NotificationManager::class.java).notify(ID_NOTIFICACAO, montarNotificacao())
    }

    // MARK: GPS do turno

    private var gps: LocationManager? = null

    private val ouvinteGps = object : LocationListener {
        override fun onLocationChanged(l: Location) {
            Rastro.adicionar(this@CapturaService, PontoGps(l.time, l.latitude, l.longitude, l.accuracy))
        }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Android antigo ainda chama")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private fun temGps() =
        checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun ligarGps(turno: Turno, t: HandlerThread) {
        Rastro.comecar(this, turno.id)
        if (!temGps()) return
        val lm = getSystemService(LocationManager::class.java)
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 3_000L, 0f, ouvinteGps, t.looper)
            gps = lm
        } catch (_: Exception) {
        }
    }

    // MARK: Gravação de tela (reserva)

    private fun iniciarGravacao(code: Int, data: Intent) {
        val h = handler ?: return
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = mpm.getMediaProjection(code, data)
        projection = proj
        // Android 14+: o callback tem que existir antes de criar o display virtual
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                if (!encerrando) stopSelf()
            }
        }, h)

        val (largReal, altuReal, dpi) = medidasDaTela()
        val escala = min(1f, 1080f / min(largReal, altuReal))
        val larg = (largReal * escala).roundToInt()
        val altu = (altuReal * escala).roundToInt()

        val leitor = ImageReader.newInstance(larg, altu, PixelFormat.RGBA_8888, 2)
        reader = leitor
        leitor.setOnImageAvailableListener({ r -> aoChegarFrame(r) }, h)
        virtualDisplay = proj.createVirtualDisplay(
            "apex", larg, altu, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            leitor.surface, null, h
        )
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

    private fun aoChegarFrame(r: ImageReader) {
        val img = try { r.acquireLatestImage() } catch (_: Exception) { null } ?: return
        val agora = SystemClock.elapsedRealtime()
        if (Estado.pausado || Estado.appNaFrente || agora - ultimoFrame < INTERVALO_MS ||
            !ocrRodando.compareAndSet(false, true)
        ) {
            img.close()
            return
        }
        ultimoFrame = agora

        val bitmap = try { paraBitmap(img) } catch (_: Throwable) { null } finally { img.close() }
        if (bitmap == null) {
            ocrRodando.set(false)
            return
        }
        Processador.executar {
            try {
                val texto = Tasks.await(reconhecedor.process(InputImage.fromBitmap(bitmap, 0)))
                Processador.analisarAgora(Ocr.ordenar(texto, bitmap.height))
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
        val larguraComBorda = plano.rowStride / plano.pixelStride
        val cheio = Bitmap.createBitmap(larguraComBorda, img.height, Bitmap.Config.ARGB_8888)
        cheio.copyPixelsFromBuffer(plano.buffer)
        val y0 = (img.height * 0.35).toInt()
        val corte = Bitmap.createBitmap(cheio, 0, y0, img.width, img.height - y0)
        if (corte !== cheio) cheio.recycle()
        return corte
    }

    // MARK: Encerramento

    override fun onDestroy() {
        encerrando = true
        if (ativo) {
            gps?.removeUpdates(ouvinteGps)
            Rastro.parar(this)
            virtualDisplay?.release()
            reader?.close()
            try { projection?.stop() } catch (_: Exception) {}
            Processador.encerrar()
            Sobreposicao.desligar()
            TurnoStore.get(this).encerrar()
        }
        ativo = false
        Estado.pausado = false
        Estado.rodando.value = false
        thread?.quitSafely()
        super.onDestroy()
    }
}
