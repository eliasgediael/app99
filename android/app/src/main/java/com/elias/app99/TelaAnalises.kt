package com.elias.app99

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

enum class Periodo(val nome: String) { HOJE("Hoje"), SEMANA("Semana"), MES("Mês") }

private data class Ponto(val rotulo: String, val detalhe: String, val resumo: Resumo?)

@Composable
fun TelaAnalises(abrir: (Detalhe) -> Unit) {
    val ctx = LocalContext.current
    val painel = lembrarPainel()
    val agora = lembrarAgora()
    val config = remember(painel) { Ajustes.config(ctx) }
    var periodo by rememberSaveable { mutableStateOf(Periodo.SEMANA) }
    var selecionada by remember(periodo) { mutableStateOf<Int?>(null) }

    val hoje = LocalDate.now()
    val inicio = when (periodo) {
        Periodo.HOJE -> hoje
        Periodo.SEMANA -> hoje.minusDays(6)
        Periodo.MES -> hoje.withDayOfMonth(1)
    }
    val r = painel.resumo(inicio, hoje, agora)

    Column(Modifier.fillMaxSize()) {
        BarraTopo("Análises", null)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Segmentos(Periodo.entries.toList(), { it.nome }, periodo) { periodo = it }

            if (!r.temDados) {
                EstadoVazio("Sem dados neste período")
                return@Column
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Indicador(Formato.reais(r.faturado), "Total de ganhos", Modifier.weight(1f))
                Indicador("${r.confirmadas.size}", "Corridas", Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Indicador(r.porHora?.let { Formato.reais(it) + "/h" } ?: "—", "Média por hora", Modifier.weight(1f))
                Indicador(r.porKm?.let { Formato.reais(it) + "/km" } ?: "—", "Média por km", Modifier.weight(1f))
            }

            // Barras: horas de hoje, os 7 dias ou os dias do mês. Sem dado = sem barra.
            val pontos: List<Ponto> = when (periodo) {
                Periodo.HOJE -> (0..23).mapNotNull { h ->
                    val lista = r.corridas.filter { c -> c.confirmada && c.termino?.let { horaDe(it) == h } == true }
                    if (lista.isEmpty()) null else Ponto("${h}h", "${h}h–${h + 1}h", Resumo(lista, 0))
                }
                Periodo.SEMANA -> (6 downTo 0).map { i ->
                    val d = hoje.minusDays(i.toLong())
                    val rd = painel.resumo(d, d, agora)
                    Ponto(if (i == 0) "Hoje" else nomeDia(d), dataLonga(d), rd.takeIf { it.temDados })
                }
                Periodo.MES -> (1..hoje.dayOfMonth).map { dia ->
                    val d = hoje.withDayOfMonth(dia)
                    val rd = painel.resumo(d, d, agora)
                    Ponto(if (dia % 5 == 0 || dia == 1) "$dia" else "", dataLonga(d), rd.takeIf { it.temDados })
                }
            }
            if (pontos.any { it.resumo != null }) {
                Cartao {
                    val sel = selecionada?.let { pontos.getOrNull(it) }
                    if (sel?.resumo != null) {
                        Text(
                            "${sel.detalhe} · ${Formato.reais(sel.resumo.faturado)} · ${sel.resumo.confirmadas.size} corridas",
                            color = Cor.texto, fontSize = 13.sp, fontWeight = FontWeight.SemiBold
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                    GraficoBarras(
                        pontos.mapIndexed { i, p ->
                            Barra(p.rotulo, p.resumo?.faturado, destaque = i == pontos.lastIndex && periodo != Periodo.HOJE)
                        },
                        selecionada, { selecionada = it }
                    )
                }
            }

            val classes = r.corridas.filter { it.feita }.mapNotNull { Corridas.classificar(it, config) }
            if (classes.isNotEmpty()) {
                Cartao {
                    Text("Tipos de corrida", color = Cor.texto, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(14.dp))
                    Rosca(
                        Veredito.entries.map { v -> Fatia(v.curto, classes.count { it == v }.toDouble(), v.cor) }
                            .filter { it.valor > 0 }
                    )
                }
            }
        }
    }
}

@Composable
private fun Indicador(valor: String, rotulo: String, modifier: Modifier = Modifier) {
    Box(modifier) {
        Cartao(espaco = 14.dp) {
            Text(valor, color = Cor.texto, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(rotulo, color = Cor.texto2, fontSize = 13.sp)
        }
    }
}

private fun horaDe(epochSeg: Long): Int =
    java.time.Instant.ofEpochSecond(epochSeg).atZone(java.time.ZoneId.systemDefault()).hour

private fun nomeDia(d: LocalDate): String =
    d.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale("pt", "BR")).replace(".", "")
        .replaceFirstChar { it.uppercase() }.take(3)
