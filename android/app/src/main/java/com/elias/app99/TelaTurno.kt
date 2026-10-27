package com.elias.app99

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.PriorityHigh
import androidx.compose.material.icons.rounded.Route
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun Logo(modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(30.dp).clip(RoundedCornerShape(9.dp))
                .background(Brush.linearGradient(listOf(Cor.azul, Color(0xFF60A5FA)))),
            contentAlignment = Alignment.Center
        ) { Text("A", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black) }
        Spacer(Modifier.width(10.dp))
        Text("Apex", color = Cor.texto, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun TelaTurno(acoes: AcoesTurno, abrir: (Detalhe) -> Unit, verTodas: () -> Unit) {
    val ctx = LocalContext.current
    val painel = lembrarPainel()
    val agora = lembrarAgora()
    val rodando by Estado.rodando.collectAsState()
    val config = remember(painel) { Ajustes.config(ctx) }
    val meta = remember(painel) { Ajustes.metaDiaria(ctx) }
    val turno = painel.turnos.lastOrNull { it.ativo }
    val hoje = LocalDate.now()
    val resumoHoje = painel.resumo(hoje, hoje, agora)
    val resumo = turno?.let { painel.resumoTurno(it, agora) } ?: resumoHoje

    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).statusBarsPadding()
                .padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Logo(Modifier.weight(1f))
                IconButton(onClick = { abrir(Detalhe.Configuracoes) }) {
                    Icon(Icons.Rounded.Settings, "Configurações", tint = Cor.texto2)
                }
            }

            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                when {
                    turno == null -> Pilula("SEM TURNO ATIVO", Cor.texto2)
                    turno.pausado -> Pilula("TURNO PAUSADO · ${Formato.duracao(turno.duracaoMs(agora))}", Cor.ambar)
                    else -> Pilula("TURNO ATIVO · ${Formato.duracao(turno.duracaoMs(agora))}", Cor.verde)
                }
            }

            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    Formato.reais(resumo.faturado), color = Cor.texto,
                    fontSize = 46.sp, fontWeight = FontWeight.Bold
                )
                val n = resumo.confirmadas.size
                val sufixo = if (turno == null) " hoje" else ""
                Text("($n corrida${if (n == 1) "" else "s"}$sufixo)", color = Cor.texto2, fontSize = 15.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricaCartao(
                    Icons.Rounded.Speed, resumo.porHora?.let { Formato.reais(it) + "/h" } ?: "—",
                    "Média por hora", Modifier.weight(1f)
                )
                MetricaCartao(
                    Icons.Rounded.Route, resumo.porKm?.let { Formato.reais(it) + "/km" } ?: "—",
                    "Média por km", Modifier.weight(1f)
                )
            }

            if (meta > 0) {
                Cartao {
                    Row(Modifier.fillMaxWidth()) {
                        Text("Meta diária", color = Cor.texto, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Text(Formato.reais(meta), color = Cor.texto, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.height(10.dp))
                    val fracao = (resumoHoje.faturado / meta).toFloat()
                    BarraProgresso(fracao, Cor.verde)
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth()) {
                        Text("${(fracao * 100).toInt().coerceAtMost(999)}%", color = Cor.texto2, fontSize = 13.sp,
                            modifier = Modifier.weight(1f))
                        val falta = meta - resumoHoje.faturado
                        Text(
                            if (falta > 0) "Faltam ${Formato.reais(falta)}" else "Meta atingida",
                            color = if (falta > 0) Cor.texto2 else Cor.verde, fontSize = 13.sp
                        )
                    }
                }
            }

            val ultimas = painel.corridas.filter { it.feita }.sortedByDescending { it.termino ?: 0 }.take(5)
            Cartao(espaco = 14.dp) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Últimas corridas", color = Cor.texto, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Text("Ver todas", color = Cor.azul, fontSize = 13.sp, modifier = Modifier.clickable(onClick = verTodas))
                }
                if (ultimas.isEmpty()) {
                    EstadoVazio("Nenhuma corrida ainda")
                } else {
                    ultimas.forEachIndexed { i, c ->
                        if (i > 0) Divisor()
                        LinhaCorrida(c, Corridas.classificar(c, config))
                    }
                }
            }
        }

        AcoesRodape(turno, rodando, acoes)
    }
}

@Composable
private fun AcoesRodape(turno: Turno?, rodando: Boolean, acoes: AcoesTurno) {
    Row(
        Modifier.fillMaxWidth().background(Cor.fundo).padding(horizontal = 18.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (turno == null || !rodando) {
            Button(
                onClick = acoes.iniciar, modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp), colors = ButtonDefaults.buttonColors(containerColor = Cor.azul)
            ) { Text(if (turno == null) "Iniciar turno" else "Retomar leitura", fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
        } else {
            OutlinedButton(
                onClick = if (turno.pausado) acoes.retomar else acoes.pausar,
                modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(14.dp)
            ) { Text(if (turno.pausado) "Retomar" else "Pausar", color = Cor.texto, fontSize = 16.sp) }
            Button(
                onClick = acoes.encerrar, modifier = Modifier.weight(1f).height(52.dp),
                shape = RoundedCornerShape(14.dp), colors = ButtonDefaults.buttonColors(containerColor = Cor.vermelho)
            ) { Text("Encerrar", fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
        }
    }
}

private val hora = DateTimeFormatter.ofPattern("HH:mm")

/** Corrida numa lista: ícone com a classificação, valor, nota e km, horário. */
@Composable
fun LinhaCorrida(c: CorridaResumo, v: Veredito?) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        val cor = v?.cor ?: Cor.texto3
        Box(
            Modifier.size(30.dp).clip(CircleShape).background(cor.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                when (v) {
                    Veredito.BOA -> Icons.Rounded.Check
                    Veredito.ACEITAVEL -> Icons.Rounded.PriorityHigh
                    Veredito.RUIM -> Icons.Rounded.Close
                    null -> Icons.Rounded.Check
                },
                null, tint = cor, modifier = Modifier.size(17.dp)
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                (if (c.estimada) "≈ " else "") + (c.valor?.let { Formato.reais(it) } ?: "—"),
                color = if (c.estimada) Cor.ambar else Cor.texto, fontSize = 16.sp, fontWeight = FontWeight.Bold
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                c.nota?.let {
                    Icon(Icons.Rounded.Star, null, tint = Cor.ambar, modifier = Modifier.size(13.dp))
                    Spacer(Modifier.width(3.dp))
                    Text(Formato.nota(it) + "  ·  ", color = Cor.texto2, fontSize = 12.sp)
                }
                Text(c.km?.let { Formato.km(it) } ?: "", color = Cor.texto2, fontSize = 12.sp)
            }
        }
        Text(
            c.termino?.let { Instant.ofEpochSecond(it).atZone(ZoneId.systemDefault()).format(hora) } ?: "",
            color = Cor.texto2, fontSize = 13.sp
        )
    }
}
