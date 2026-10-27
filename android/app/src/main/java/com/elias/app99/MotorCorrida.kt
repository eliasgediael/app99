package com.elias.app99

import kotlin.math.roundToInt

/** O que a leitura viu em um frame (já classificado). */
sealed class TelaLida {
    data class Oferta(val o: OfertaCorrida) : TelaLida()
    object ACaminho : TelaLida()
    object Embarque : TelaLida()
    object ABordo : TelaLida()
    data class Fim(val valorCent: Int?) : TelaLida()
    object Cancelada : TelaLida()
    object Outra : TelaLida()

    /** Chave pra comparar frames (ofertas diferentes têm chaves diferentes). */
    val classe: String
        get() = when (this) {
            is Oferta -> "oferta:" + MotorCorrida.chave(o)
            ACaminho -> "aCaminho"
            Embarque -> "embarque"
            ABordo -> "aBordo"
            is Fim -> "fim"
            Cancelada -> "cancelada"
            Outra -> "outra"
        }
}

/** Quem guarda o que o motor decide. */
interface RegistroMotor {
    fun novoIdOferta(): Int
    fun novoIdCorrida(): Int
    fun contarOferta()
    fun somarConfirmada(valorCent: Int, custoCent: Int, metros: Int)
    fun somarEstimada(valorCent: Int)
    fun adicionar(evento: EventoLinha)
}

/**
 * Máquina de estados das corridas. É o ÚNICO lugar que decide estado e faturamento.
 *
 * - Oferta na tela / saindo da tela nunca vira corrida nem faturamento.
 * - Aceite só liga a uma oferta se vier até 60 s depois de ela sair da tela e nenhuma outra oferta
 *   tiver sido lida no meio. Na dúvida: sem valor.
 * - Durante uma corrida, a 99 mostra "cancelou" logo depois de cada oferta que você NÃO aceita:
 *   "cancelou" até 8 s depois de uma oferta sair vale pra oferta, nunca pra sua corrida.
 * - A 99 só mostra o aceite da próxima corrida depois de você finalizar a atual.
 * - CONFIRMADA = aceite + valor + passageiro a bordo + tela de fim. Só ela soma no faturamento.
 * - ESTIMADA = aceite + valor + (a bordo OU fim). Soma separado.
 * - Resto = INDETERMINADA (R$ 0).
 * - Toda tela precisa ser lida 2 vezes em até 3 s pra valer (evita erro de OCR de um frame só).
 *
 * Usar sempre na mesma thread.
 */
class MotorCorrida(private val diario: RegistroMotor) {

    private class Corrida(
        val id: Int,
        var estado: EstadoCorrida,
        val criadaEm: Long,
        var ultimaTela: Long,
        var oferta: OfertaCorrida?,
        var ofertaId: Int = 0,
        var ligacaoConfirmada: Boolean = false,
        var aceite: Boolean
    ) {
        var aBordo = false
        var fim = false
        var chegouEmbarque = false
        var valorFinalCent: Int? = null
    }

    private class OfertaVista(
        val oferta: OfertaCorrida,
        val id: Int,
        val chave: String,
        val primeiraVez: Long
    ) {
        var saiuEm: Long? = null
        var cancelada = false   // "cancelou" logo depois de sair: não foi aceita
    }

    private class Candidata(val classe: String, val tela: TelaLida, val primeira: Long)

    /** Custo por km atual (vem dos ajustes); usado no custo das corridas confirmadas. */
    var custoPorKm: Double = ConfigMoto().custoPorKm

    private val abertas = mutableListOf<Corrida>()
    private var ultimaOferta: OfertaVista? = null
    private val chavesAlheias = mutableSetOf<String>()
    private val registradasEm = mutableMapOf<String, Pair<Long, Int>>()
    private val fila = mutableListOf<OfertaVista>()

    private var classeAtual = "outra"
    private var candidata: Candidata? = null

    private val janelaDebounce = 3.0
    private val janelaAceite = 60.0
    private val janelaAceiteConfirmado = 30.0
    private val janelaCancelOferta = 8.0
    private val validadeFila = 30 * 60.0
    private val limiteCorridaAberta = 3 * 3600.0

    private fun seg(a: Long, b: Long) = (a - b) / 1000.0

    companion object {
        /** Leituras erradas da tela de busca viram "ofertas" de R$ 8 com 1 m de viagem. */
        fun plausivel(o: OfertaCorrida) = o.valor >= 3 && o.kmViagem >= 0.3

        fun chave(o: OfertaCorrida): String =
            String.format(java.util.Locale.US, "%.2f|%.2f|%.2f", o.valor, o.kmAtePassageiro, o.kmViagem)
    }

    // MARK: Entrada

    fun observar(telaLida: TelaLida, agora: Long = System.currentTimeMillis()) {
        encerrarVelhas(agora)
        var tela = telaLida
        if (tela is TelaLida.Oferta && !plausivel(tela.o)) tela = TelaLida.Outra

        // Qualquer oferta lida, mesmo num frame só, conta pra ambiguidade do aceite
        if (tela is TelaLida.Oferta) {
            val ch = chave(tela.o)
            if (ch != ultimaOferta?.chave) chavesAlheias.add(ch)
        }

        val classe = tela.classe
        if (classe == classeAtual) {
            candidata = null
            return
        }
        val c = candidata
        if (c != null && c.classe == classe && seg(agora, c.primeira) <= janelaDebounce) {
            val anterior = classeAtual
            classeAtual = classe
            candidata = null
            mudou(anterior, tela, agora)
        } else {
            candidata = Candidata(classe, tela, agora)
        }
    }

    /** Leitura desligando: fecha o que estiver aberto com o que se sabe. */
    fun encerrarTudo(agora: Long = System.currentTimeMillis()) {
        for (c in abertas.toList()) encerrar(c, agora, Motivo.LEITURA_ENCERRADA)
        abertas.clear()
        classeAtual = "outra"
        candidata = null
        ultimaOferta = null
        chavesAlheias.clear()
        fila.clear()
    }

    // MARK: Transições

    private fun mudou(anterior: String, tela: TelaLida, agora: Long) {
        // Oferta saindo da tela: só registra. NUNCA vira corrida nem faturamento.
        val ov = ultimaOferta
        if (anterior.startsWith("oferta:") && ov != null && anterior == "oferta:" + ov.chave && ov.saiuEm == null) {
            ov.saiuEm = agora
            when (tela) {
                is TelaLida.ACaminho, is TelaLida.Embarque -> {}   // o aceite registra
                is TelaLida.Oferta, is TelaLida.Cancelada ->
                    evento(TipoEvento.OFERTA_SAIU_DA_TELA, OrigemEvento.TELA, agora,
                        motivo = Motivo.OFERTA_SAIU_SEM_ACEITE, oferta = ov.oferta, ofertaId = ov.id)
                else -> {
                    evento(TipoEvento.OFERTA_SAIU_DA_TELA, OrigemEvento.TELA, agora,
                        motivo = Motivo.OFERTA_SAIU_SEM_ACEITE, oferta = ov.oferta, ofertaId = ov.id)
                    // Com corrida em andamento, oferta que sai sem "cancelou" foi aceita pra depois.
                    if (abertas.isNotEmpty() || fila.isNotEmpty()) fila.add(ov)
                }
            }
        }

        when (tela) {
            is TelaLida.Oferta -> ofertaNaTela(tela.o, agora)
            is TelaLida.ACaminho -> telaDeAceite(false, agora)
            is TelaLida.Embarque -> telaDeAceite(true, agora)
            is TelaLida.ABordo -> passageiroABordo(agora)
            is TelaLida.Fim -> fimDeCorrida(tela.valorCent, agora)
            is TelaLida.Cancelada -> cancelamento(agora)
            is TelaLida.Outra -> {}
        }
    }

    private fun ofertaNaTela(o: OfertaCorrida, agora: Long) {
        val ch = chave(o)
        registradasEm.entries.removeAll { seg(agora, it.value.first) >= 20 }
        // Mesma oferta voltando pra tela em menos de 20 s: mesmo id, sem novo evento
        val ja = registradasEm[ch]
        if (ja != null) {
            ultimaOferta = OfertaVista(o, ja.second, ch, agora)
            chavesAlheias.clear()
            return
        }
        val id = diario.novoIdOferta()
        registradasEm[ch] = Pair(agora, id)
        ultimaOferta = OfertaVista(o, id, ch, agora)
        chavesAlheias.clear()
        diario.contarOferta()
        var minutos = 0
        if (o.minAtePassageiro != null || o.minViagem != null) {
            minutos = (o.minAtePassageiro ?: 0) * 1000 + (o.minViagem ?: 0)
        }
        evento(TipoEvento.OFERTA_DETECTADA, OrigemEvento.TELA, agora,
            motivo = Motivo.LIDO_NA_TELA, oferta = o, ofertaId = id, minutos = minutos)
    }

    private fun telaDeAceite(embarque: Boolean, agora: Long) {
        // Corrida já aceita e ainda sem passageiro: é a mesma
        val i = abertas.indexOfLast { it.estado == EstadoCorrida.ACEITA || it.estado == EstadoCorrida.A_CAMINHO }
        if (i >= 0) {
            val c = abertas[i]
            c.ultimaTela = agora
            if (embarque && !c.chegouEmbarque) {
                c.chegouEmbarque = true
                evento(TipoEvento.TELA_EMBARQUE, OrigemEvento.TELA, agora,
                    corrida = c.id, motivo = Motivo.MESMA_CORRIDA_NA_TELA)
            }
            return
        }

        // A 99 só mostra o aceite da próxima depois de finalizar a atual: a que estava em andamento acabou
        val emAndamento = abertas.filter { it.estado == EstadoCorrida.EM_CORRIDA }
        abertas.removeAll { it.estado == EstadoCorrida.EM_CORRIDA }
        for (c in emAndamento) {
            c.fim = true
            evento(TipoEvento.TRANSICAO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
                de = c.estado, para = EstadoCorrida.FIM_DETECTADO, motivo = Motivo.FIM_INFERIDO_POR_NOVO_ACEITE)
            c.estado = EstadoCorrida.FIM_DETECTADO
            encerrar(c, agora, null)
        }

        // Novo aceite: primeiro a oferta aceita durante a corrida anterior; senão a que acabou de sair da tela
        var ligada: OfertaVista? = null
        var confirmada = false
        var motivo = Motivo.ACEITE_SEM_OFERTA
        var extra = 0
        if (fila.isNotEmpty()) {
            extra = fila.size
            ligada = fila.removeAt(0)
            confirmada = extra == 1
            motivo = Motivo.OFERTA_ACEITA_DURANTE_CORRIDA
        } else {
            val ov = ultimaOferta
            if (ov != null && !ov.cancelada) {
                val saiu = ov.saiuEm ?: agora
                val segundos = seg(agora, saiu)
                if (segundos <= janelaAceite) {
                    if (chavesAlheias.isEmpty()) {
                        ligada = ov
                        confirmada = segundos <= janelaAceiteConfirmado
                        motivo = if (confirmada) Motivo.OFERTA_LIGADA_AO_ACEITE else Motivo.OFERTA_LIGADA_FRACA
                        extra = segundos.toInt()
                    } else {
                        motivo = Motivo.ACEITE_OFERTA_AMBIGUA
                    }
                }
            }
        }
        ultimaOferta = null
        chavesAlheias.clear()

        val id = novaCorrida(ligada, confirmada, motivo, extra, OrigemEvento.TELA, agora)
        if (embarque) {
            abertas.lastOrNull { it.id == id }?.chegouEmbarque = true
            evento(TipoEvento.TELA_EMBARQUE, OrigemEvento.TELA, agora, corrida = id, motivo = Motivo.LIDO_NA_TELA)
        }
    }

    /** Abre uma corrida aceita (vista na tela ou inferida) e registra o aceite na linha do tempo. */
    private fun novaCorrida(ligada: OfertaVista?, confirmada: Boolean, motivo: Motivo, extra: Int,
                            origem: OrigemEvento, agora: Long): Int {
        val id = diario.novoIdCorrida()
        val c = Corrida(id, EstadoCorrida.ACEITA, agora, agora, ligada?.oferta,
            ofertaId = ligada?.id ?: 0, ligacaoConfirmada = confirmada, aceite = true)
        evento(TipoEvento.ACEITE_DETECTADO, origem, agora, corrida = id, para = EstadoCorrida.ACEITA,
            confianca = if (ligada == null) Confianca.INDETERMINADO
                        else if (confirmada) Confianca.CONFIRMADO else Confianca.ESTIMADO,
            motivo = motivo, extra = extra, oferta = ligada?.oferta, ofertaId = ligada?.id ?: 0)
        evento(TipoEvento.TRANSICAO, origem, agora, corrida = id,
            de = EstadoCorrida.ACEITA, para = EstadoCorrida.A_CAMINHO,
            motivo = if (origem == OrigemEvento.TELA) Motivo.LIDO_NA_TELA else Motivo.ACEITE_INFERIDO_PELO_FIM)
        c.estado = EstadoCorrida.A_CAMINHO
        abertas.add(c)
        return id
    }

    /** Corrida aceita durante a anterior cuja tela de aceite não foi vista: abre a partir da fila. */
    private fun abrirDaFila(agora: Long): Boolean {
        if (fila.isEmpty()) return false
        val n = fila.size
        val ov = fila.removeAt(0)
        novaCorrida(ov, n == 1, Motivo.ACEITE_INFERIDO_PELO_FIM, n, OrigemEvento.INFERENCIA, agora)
        return true
    }

    private fun passageiroABordo(agora: Long) {
        val i = abertas.indexOfFirst { it.estado == EstadoCorrida.ACEITA || it.estado == EstadoCorrida.A_CAMINHO }
        if (i >= 0) {
            val c = abertas[i]
            val de = c.estado
            c.aBordo = true
            c.ultimaTela = agora
            evento(TipoEvento.PASSAGEIRO_A_BORDO, OrigemEvento.TELA, agora, corrida = c.id, motivo = Motivo.LIDO_NA_TELA)
            evento(TipoEvento.TRANSICAO, OrigemEvento.TELA, agora, corrida = c.id,
                de = de, para = EstadoCorrida.PASSAGEIRO_A_BORDO, motivo = Motivo.LIDO_NA_TELA)
            evento(TipoEvento.TRANSICAO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
                de = EstadoCorrida.PASSAGEIRO_A_BORDO, para = EstadoCorrida.EM_CORRIDA,
                motivo = Motivo.A_BORDO_IMPLICA_EM_CORRIDA)
            c.estado = EstadoCorrida.EM_CORRIDA
            return
        }
        val j = abertas.indexOfLast { it.estado == EstadoCorrida.EM_CORRIDA }
        if (j >= 0) {
            abertas[j].ultimaTela = agora   // mesma corrida voltando pra tela
            return
        }
        // Aceite não visto, mas havia oferta aceita durante a corrida anterior
        if (abrirDaFila(agora)) {
            passageiroABordo(agora)
            return
        }
        // A bordo sem aceite: registra, mas nunca vai ter valor confirmado
        val id = diario.novoIdCorrida()
        val c = Corrida(id, EstadoCorrida.PASSAGEIRO_A_BORDO, agora, agora, null, aceite = false)
        c.aBordo = true
        evento(TipoEvento.PASSAGEIRO_A_BORDO, OrigemEvento.TELA, agora, corrida = id,
            para = EstadoCorrida.PASSAGEIRO_A_BORDO, motivo = Motivo.A_BORDO_SEM_ACEITE)
        evento(TipoEvento.TRANSICAO, OrigemEvento.INFERENCIA, agora, corrida = id,
            de = EstadoCorrida.PASSAGEIRO_A_BORDO, para = EstadoCorrida.EM_CORRIDA,
            motivo = Motivo.A_BORDO_IMPLICA_EM_CORRIDA)
        c.estado = EstadoCorrida.EM_CORRIDA
        abertas.add(c)
    }

    private fun fimDeCorrida(valorCent: Int?, agora: Long) {
        var i = abertas.indexOfFirst { it.estado == EstadoCorrida.EM_CORRIDA }
        if (i < 0) i = abertas.indexOfLast { it.estado == EstadoCorrida.ACEITA || it.estado == EstadoCorrida.A_CAMINHO }
        if (i < 0) {
            if (abrirDaFila(agora)) {
                fimDeCorrida(valorCent, agora)
                return
            }
            evento(TipoEvento.FIM_DETECTADO, OrigemEvento.TELA, agora,
                motivo = Motivo.FIM_SEM_CORRIDA_ABERTA, valorCent = valorCent ?: 0)
            return
        }
        val c = abertas.removeAt(i)
        c.fim = true
        c.valorFinalCent = valorCent
        evento(TipoEvento.FIM_DETECTADO, OrigemEvento.TELA, agora, corrida = c.id,
            motivo = if (valorCent != null) Motivo.VALOR_FINAL_LIDO_NA_TELA else Motivo.LIDO_NA_TELA,
            valorCent = valorCent ?: 0)
        evento(TipoEvento.TRANSICAO, OrigemEvento.TELA, agora, corrida = c.id,
            de = c.estado, para = EstadoCorrida.FIM_DETECTADO, motivo = Motivo.LIDO_NA_TELA)
        c.estado = EstadoCorrida.FIM_DETECTADO
        encerrar(c, agora, null)
    }

    private fun cancelamento(agora: Long) {
        // "cancelou" logo depois de uma oferta sair da tela: é a oferta (não aceita), não a sua corrida
        val ov = ultimaOferta
        val saiu = ov?.saiuEm
        if (ov != null && saiu != null && !ov.cancelada && seg(agora, saiu) <= janelaCancelOferta) {
            ov.cancelada = true
            fila.removeAll { it.id == ov.id }
            evento(TipoEvento.CANCELAMENTO_DETECTADO, OrigemEvento.TELA, agora,
                motivo = Motivo.OFERTA_CANCELADA_NA_TELA, oferta = ov.oferta, ofertaId = ov.id)
            return
        }
        val i = abertas.indexOfLast { it.estado == EstadoCorrida.ACEITA || it.estado == EstadoCorrida.A_CAMINHO }
        if (i < 0) {
            evento(TipoEvento.CANCELAMENTO_DETECTADO, OrigemEvento.TELA, agora, motivo = Motivo.CANCELAMENTO_SEM_CORRIDA)
            return
        }
        val c = abertas.removeAt(i)
        evento(TipoEvento.CANCELAMENTO_DETECTADO, OrigemEvento.TELA, agora, corrida = c.id, motivo = Motivo.LIDO_NA_TELA)
        evento(TipoEvento.TRANSICAO, OrigemEvento.TELA, agora, corrida = c.id,
            de = c.estado, para = EstadoCorrida.CANCELADA, motivo = Motivo.CANCELADA_NA_TELA)
        evento(TipoEvento.SEM_FATURAMENTO, OrigemEvento.INFERENCIA, agora, corrida = c.id, motivo = Motivo.CANCELADA_NA_TELA)
    }

    private fun encerrarVelhas(agora: Long) {
        val velhas = abertas.filter { seg(agora, it.criadaEm) > limiteCorridaAberta }
        fila.removeAll { seg(agora, it.saiuEm ?: it.primeiraVez) > validadeFila }
        if (velhas.isEmpty()) return
        abertas.removeAll { seg(agora, it.criadaEm) > limiteCorridaAberta }
        for (c in velhas) encerrar(c, agora, Motivo.TEMPO_ESGOTADO)
    }

    // MARK: Decisão final

    /** Classifica pela evidência e só aí mexe em dinheiro. `porque` = motivo de fechar sem tela de fim. */
    private fun encerrar(c: Corrida, agora: Long, porque: Motivo?) {
        val valorCent: Int? = c.valorFinalCent ?: c.oferta?.let { (it.valor * 100).roundToInt() }
        // Valor confirmado = lido na tela de fim, ou oferta ligada ao aceite com associação confirmada
        val valorConfirmado = c.valorFinalCent != null || (c.oferta != null && c.ligacaoConfirmada)

        var falta = 0
        if (!c.aceite) falta = falta or Falta.ACEITE
        if (valorCent == null) falta = falta or Falta.VALOR
        else if (!valorConfirmado) falta = falta or Falta.LIGACAO
        if (!c.aBordo && !c.fim) falta = falta or Falta.A_BORDO   // tela de fim implica passageiro a bordo
        if (!c.fim) falta = falta or Falta.FIM

        val estadoFinal: EstadoCorrida
        val confianca: Confianca
        if (falta == 0) {
            estadoFinal = EstadoCorrida.CONFIRMADA; confianca = Confianca.CONFIRMADO
        } else if (c.aceite && valorCent != null && (c.aBordo || c.fim)) {
            estadoFinal = EstadoCorrida.ESTIMADA; confianca = Confianca.ESTIMADO
        } else {
            estadoFinal = EstadoCorrida.INDETERMINADA; confianca = Confianca.INDETERMINADO
        }

        val motivo = porque ?: if (falta == 0) Motivo.EVIDENCIA_COMPLETA else Motivo.EVIDENCIA_INCOMPLETA
        evento(TipoEvento.TRANSICAO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
            de = c.estado, para = estadoFinal, confianca = confianca, motivo = motivo,
            extra = falta, oferta = c.oferta, ofertaId = c.ofertaId)

        when (estadoFinal) {
            EstadoCorrida.CONFIRMADA -> {
                val km = c.oferta?.let { it.kmAtePassageiro + it.kmViagem } ?: 0.0
                diario.somarConfirmada(
                    valorCent ?: 0,
                    (km * custoPorKm * 100).roundToInt(),
                    (km * 1000).roundToInt()
                )
                evento(TipoEvento.FATURAMENTO_CONFIRMADO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
                    confianca = Confianca.CONFIRMADO, motivo = Motivo.EVIDENCIA_COMPLETA, valorCent = valorCent ?: 0)
            }
            EstadoCorrida.ESTIMADA -> {
                diario.somarEstimada(valorCent ?: 0)
                evento(TipoEvento.FATURAMENTO_ESTIMADO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
                    confianca = Confianca.ESTIMADO, motivo = Motivo.EVIDENCIA_INCOMPLETA,
                    extra = falta, valorCent = valorCent ?: 0)
            }
            else -> evento(TipoEvento.SEM_FATURAMENTO, OrigemEvento.INFERENCIA, agora, corrida = c.id,
                confianca = Confianca.INDETERMINADO, motivo = Motivo.EVIDENCIA_INCOMPLETA, extra = falta)
        }
    }

    // MARK: Evento

    private fun evento(
        tipo: TipoEvento, origem: OrigemEvento, agora: Long,
        corrida: Int = 0, de: EstadoCorrida? = null, para: EstadoCorrida? = null,
        confianca: Confianca? = null, motivo: Motivo = Motivo.NENHUM, extra: Int = 0,
        oferta: OfertaCorrida? = null, ofertaId: Int = 0, minutos: Int = 0, valorCent: Int = 0
    ) {
        val e = EventoLinha(em = agora / 1000, tipo = tipo, origem = origem)
        e.oferta = ofertaId
        e.minutos = minutos
        e.corrida = corrida
        e.estadoAnterior = de
        e.estadoNovo = para
        e.confianca = confianca
        e.motivo = motivo
        e.extra = extra
        e.valorCent = valorCent
        if (oferta != null) {
            if (valorCent == 0) e.valorCent = (oferta.valor * 100).roundToInt()
            e.buscaM = (oferta.kmAtePassageiro * 1000).roundToInt()
            e.viagemM = (oferta.kmViagem * 1000).roundToInt()
            e.nota100 = oferta.notaPassageiro?.let { (it * 100).roundToInt() } ?: 0
        }
        diario.adicionar(e)
    }
}
