package com.elias.app99

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONArray
import java.io.File

/** Estado compartilhado entre o serviço de leitura e a tela. */
object Estado {
    val rodando = MutableStateFlow(false)
    val ultimaAnalise = MutableStateFlow<AnaliseCorrida?>(null)

    /** O Apex está aberto na tela: o serviço não lê (seria a tela do próprio Apex). */
    @Volatile var appNaFrente = false
        set(v) {
            field = v
            naFrente.value = v
        }

    /** Mesmo valor, pra tela (a bolha some com o Apex aberto). */
    val naFrente = MutableStateFlow(false)

    /** Turno pausado: nenhuma leitura é feita. */
    @Volatile var pausado = false

    /** Último app lido pela acessibilidade (diagnóstico). */
    val pacoteLido = MutableStateFlow<String?>(null)
}

/** Ajustes do usuário (valores da moto, voz). */
object Ajustes {
    private fun p(c: Context) = c.getSharedPreferences("ajustes", Context.MODE_PRIVATE)

    fun valor(c: Context, chave: String, padrao: Double): Double =
        p(c).getString(chave, null)?.toDoubleOrNull() ?: padrao

    fun salvar(c: Context, chave: String, v: Double) {
        p(c).edit().putString(chave, v.toString()).apply()
    }

    fun texto(c: Context, chave: String, padrao: Double): String =
        valor(c, chave, padrao).toString().replace('.', ',')

    fun config(c: Context): ConfigMoto {
        val d = ConfigMoto()
        return ConfigMoto(
            custoPorKm = valor(c, "custoPorKm", d.custoPorKm),
            minimoPorKm = valor(c, "minimoPorKm", d.minimoPorKm),
            bomPorKm = valor(c, "bomPorKm", d.bomPorKm),
            alertaBuscaKm = valor(c, "alertaBuscaKm", d.alertaBuscaKm),
            notaMinima = valor(c, "notaMinima", d.notaMinima),
            lucroMinimo = valor(c, "lucroMinimo", d.lucroMinimo)
        )
    }

    /** "acessibilidade" (padrão) ou "gravacao" (reserva). */
    fun modoLeitura(c: Context): String =
        p(c).getString("modoLeitura", LeituraAcessibilidade.MODO_ACESSIBILIDADE) ?: LeituraAcessibilidade.MODO_ACESSIBILIDADE

    fun definirModoLeitura(c: Context, modo: String) {
        p(c).edit().putString("modoLeitura", modo).apply()
    }

    /** Meta do dia em R$ (0 = sem meta). */
    fun metaDiaria(c: Context) = valor(c, "metaDiaria", 0.0)

    fun chave(c: Context, nome: String, padrao: Boolean) = p(c).getBoolean(nome, padrao)
    fun definirChave(c: Context, nome: String, valor: Boolean) {
        p(c).edit().putBoolean(nome, valor).apply()
    }

    /** Desligada por padrão: com música tocando, voz + 99 + música vira bagunça; a notificação basta. */
    fun vozLigada(c: Context) = p(c).getBoolean("falarResultado", false)
    fun definirVoz(c: Context, ligada: Boolean) {
        p(c).edit().putBoolean("falarResultado", ligada).apply()
    }

    /** 1,0 = velocidade normal */
    fun velocidade(c: Context) = valor(c, "velocidadeFala", 1.0).toFloat()
}

/**
 * Totais por dia + linha do tempo, guardados no aparelho (sobrevivem entre turnos e atualizações).
 * O motor e o serviço usam sempre a mesma thread; a tela só lê pelos flows.
 */
class Diario private constructor(ctx: Context) : RegistroMotor {
    private val prefs = ctx.getSharedPreferences("diario", Context.MODE_PRIVATE)
    private val arquivoEventos = File(ctx.filesDir, "linha-do-tempo.json")
    private val pasta = File(ctx.filesDir, "linha")

    val diasFlow = MutableStateFlow<List<Dia>>(emptyList())
    val eventosFlow = MutableStateFlow<List<EventoLinha>>(emptyList())

    private val dias = mutableMapOf<Int, Dia>()
    private val eventos = mutableListOf<EventoLinha>()
    private var marcoTempo: Long? = null

    companion object {
        private const val RETENCAO_DIAS = 90
        @Volatile private var inst: Diario? = null

        fun get(ctx: Context): Diario =
            inst ?: synchronized(this) { inst ?: Diario(ctx.applicationContext).also { inst = it } }
    }

    init {
        try {
            val arr = JSONArray(prefs.getString("dias", "[]"))
            for (i in 0 until arr.length()) {
                val d = Dia.deJson(arr.getJSONObject(i))
                dias[d.dia] = d
            }
        } catch (_: Exception) {
        }
        pasta.mkdirs()
        migrarArquivoUnico()
        val limite = diaDe(System.currentTimeMillis() / 1000) - RETENCAO_DIAS
        pasta.listFiles()?.filter { it.name.endsWith(".json") }?.sortedBy { it.name }?.forEach { f ->
            val dia = f.name.removeSuffix(".json").toLongOrNull()
            if (dia == null || dia < limite) {
                f.delete()
            } else {
                eventos.addAll(lerArquivo(f))
            }
        }
        eventos.sortBy { it.seq }
        publicar()
    }

    val hoje: Dia
        @Synchronized get() = dias[Dia.numero()] ?: Dia(Dia.numero())

    private fun publicar() {
        diasFlow.value = dias.values.sortedBy { it.dia }
        eventosFlow.value = eventos.toList()
    }

    // MARK: Totais (só o MotorCorrida chama)

    @Synchronized override fun contarOferta() = alterarHoje { it.copy(ofertas = it.ofertas + 1) }

    /** Só corrida CONFIRMADA. */
    @Synchronized override fun somarConfirmada(valorCent: Int, custoCent: Int, metros: Int) = alterarHoje {
        it.copy(
            corridas = it.corridas + 1, faturadoCent = it.faturadoCent + valorCent,
            custoCent = it.custoCent + custoCent, metros = it.metros + metros
        )
    }

    /** Corrida ESTIMADA: fica separada, fora do faturamento principal. */
    @Synchronized override fun somarEstimada(valorCent: Int) = alterarHoje {
        it.copy(estimadas = it.estimadas + 1, estimadoCent = it.estimadoCent + valorCent)
    }

    @Synchronized fun zerarHoje() {
        alterarHoje { Dia(it.dia) }
        adicionar(EventoLinha(em = System.currentTimeMillis() / 1000, tipo = TipoEvento.DIA_ZERADO,
            origem = OrigemEvento.USUARIO, motivo = Motivo.ZERADO_PELO_USUARIO))
    }

    @Synchronized override fun novoIdOferta(): Int = proximo("ofertaId")
    @Synchronized override fun novoIdCorrida(): Int = proximo("corridaId")

    private fun proximo(chave: String): Int {
        val id = prefs.getInt(chave, 0) + 1
        prefs.edit().putInt(chave, id).apply()
        return id
    }

    // MARK: Linha do tempo

    @Synchronized override fun adicionar(evento: EventoLinha) {
        evento.seq = proximo("linhaSeq")
        // Onde aconteceu: posição do GPS do turno, se for recente
        Rastro.ultima?.takeIf { evento.em * 1000 - it.t in -5_000..60_000 }?.let {
            evento.lat = it.lat
            evento.lon = it.lon
        }
        eventos.add(evento)
        gravarDia(diaDe(evento.em))
        publicar()
    }

    private fun diaDe(epochSeg: Long): Long = Dia.numero(epochSeg * 1000).toLong()

    private fun gravarDia(dia: Long) {
        try {
            val doDia = eventos.filter { diaDe(it.em) == dia }
            File(pasta, "$dia.json").writeText(JSONArray(doDia.map { it.toJson() }).toString())
        } catch (_: Exception) {
        }
    }

    private fun lerArquivo(f: File): List<EventoLinha> = try {
        val arr = JSONArray(f.readText())
        (0 until arr.length()).mapNotNull { EventoLinha.deJson(arr.getJSONObject(it)) }
    } catch (_: Exception) {
        emptyList()
    }

    /** Versões anteriores guardavam tudo num arquivo só: separa por dia uma vez e guarda o original. */
    private fun migrarArquivoUnico() {
        if (!arquivoEventos.exists()) return
        val antigos = lerArquivo(arquivoEventos)
        antigos.groupBy { diaDe(it.em) }.forEach { (dia, lista) ->
            val f = File(pasta, "$dia.json")
            val ja = if (f.exists()) lerArquivo(f) else emptyList()
            val seqs = ja.map { it.seq }.toHashSet()
            val juntos = (ja + lista.filter { it.seq !in seqs }).sortedBy { it.seq }
            try { f.writeText(JSONArray(juntos.map { it.toJson() }).toString()) } catch (_: Exception) {}
        }
        arquivoEventos.renameTo(File(arquivoEventos.parentFile, "linha-do-tempo-antigo.json"))
    }

    // MARK: Tempo com a leitura ligada

    @Synchronized fun comecarTempo() {
        marcoTempo = System.currentTimeMillis()
    }

    /** Soma o tempo desde o último marco. `forcar` grava mesmo se passou pouco tempo. */
    @Synchronized fun acumularTempo(forcar: Boolean = false) {
        val marco = marcoTempo ?: return
        val agora = System.currentTimeMillis()
        val passou = (agora - marco) / 1000
        if (!forcar && passou < 60) return
        marcoTempo = agora
        alterarHoje { it.copy(segundos = it.segundos + passou.toInt()) }
    }

    @Synchronized fun pararTempo() {
        acumularTempo(true)
        marcoTempo = null
    }

    // MARK: Persistência dos totais

    private fun alterarHoje(mudar: (Dia) -> Dia) {
        val novo = mudar(hoje)
        dias[novo.dia] = novo
        // Guarda só os últimos 60 dias
        val manter = dias.values.sortedBy { it.dia }.takeLast(60)
        dias.clear()
        manter.forEach { dias[it.dia] = it }
        prefs.edit().putString("dias", JSONArray(manter.map { it.toJson() }).toString()).apply()
        publicar()
    }
}
