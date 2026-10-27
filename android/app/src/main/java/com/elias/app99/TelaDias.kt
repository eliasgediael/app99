package com.elias.app99

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Route
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Straighten
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val ptBR = Locale("pt", "BR")
private val formatoLista = DateTimeFormatter.ofPattern("EEE, dd/MM", ptBR)
private val formatoLongo = DateTimeFormatter.ofPattern("EEEE, d 'de' MMMM", ptBR)

fun dataLonga(d: LocalDate): String = d.format(formatoLongo).replaceFirstChar { it.uppercase() }

@Composable
fun BarraTopo(titulo: String, voltar: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 6.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (voltar != null) {
            IconButton(onClick = voltar) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Voltar", tint = Cor.texto) }
        } else {
            Spacer(Modifier.width(12.dp))
        }
        Text(titulo, color = Cor.texto, fontSize = 22.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun TelaDias(abrir: (Detalhe) -> Unit) {
    val painel = lembrarPainel()
    val agora = lembrarAgora()
    val dias = remember(painel) { painel.diasComDados() }
    Column(Modifier.fillMaxSize()) {
        BarraTopo("Dias", null)
        if (dias.isEmpty()) {
            EstadoVazio("Nenhum turno registrado")
            return
        }
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(dias) { d ->
                val r = painel.resumo(d, d, agora)
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Cor.cartao)
                        .clickable { abrir(Detalhe.MeuDia(d)) }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (d == LocalDate.now()) "Hoje" else d.format(formatoLista).replaceFirstChar { it.uppercase() },
                            color = Cor.texto, fontWeight = FontWeight.SemiBold
                        )
                        val n = r.confirmadas.size
                        Text(
                            "$n corrida${if (n == 1) "" else "s"}" +
                                (if (r.onlineMs > 0) " · ${Formato.duracao(r.onlineMs)}" else ""),
                            color = Cor.texto2, fontSize = 13.sp
                        )
                    }
                    Text(Formato.reais(r.faturado), color = Cor.texto, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Cor.texto3)
                }
            }
        }
    }
}

/** Resumo do dia ("Meu dia"). */
@Composable
fun TelaMeuDia(data: LocalDate, voltar: () -> Unit, verAnalise: () -> Unit) {
    val ctx = LocalContext.current
    val painel = lembrarPainel()
    val agora = lembrarAgora()
    val config = remember(painel) { Ajustes.config(ctx) }
    val r = painel.resumo(data, data, agora)

    Column(Modifier.fillMaxSize()) {
        BarraTopo("Meu dia", voltar)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(dataLonga(data), color = Cor.texto, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Cartao {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(48.dp).clip(CircleShape).background(Cor.ambar.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) { Icon(Icons.Rounded.EmojiEvents, null, tint = Cor.ambar, modifier = Modifier.size(28.dp)) }
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Text(Formato.reais(r.faturado), color = Cor.texto, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                        val n = r.confirmadas.size
                        Text("$n corrida${if (n == 1) "" else "s"}", color = Cor.texto2)
                    }
                }
                if (r.estimadas.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "+ ≈ ${Formato.reais(r.estimado)} em ${r.estimadas.size} estimada${if (r.estimadas.size == 1) "" else "s"}",
                        color = Cor.ambar, fontSize = 13.sp
                    )
                }
                Spacer(Modifier.height(12.dp))
                Divisor()
                LinhaIcone(Icons.Rounded.Schedule, "Tempo online", if (r.onlineMs > 0) Formato.duracao(r.onlineMs) else "—")
                LinhaIcone(Icons.Rounded.Straighten, "Distância total", r.km?.let { "≈ " + Formato.km(it) } ?: "—")
                LinhaIcone(Icons.Rounded.Speed, "Média por hora", r.porHora?.let { Formato.reais(it) } ?: "—")
                LinhaIcone(Icons.Rounded.Route, "Média por km", r.porKm?.let { Formato.reais(it) } ?: "—")
                r.lucro(config)?.let { LinhaIcone(Icons.Rounded.BarChart, "Lucro estimado", Formato.reais(it)) }
            }

            Button(
                onClick = verAnalise, modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp), colors = ButtonDefaults.buttonColors(containerColor = Cor.azul)
            ) {
                Icon(Icons.Rounded.BarChart, null)
                Spacer(Modifier.width(8.dp))
                Text("Ver análise completa", fontWeight = FontWeight.SemiBold)
            }

            val lista = r.corridas.filter { it.feita }.sortedByDescending { it.termino ?: 0 }
            if (lista.isNotEmpty()) {
                Cartao(espaco = 14.dp) {
                    RotuloSecao("Corridas")
                    lista.forEachIndexed { i, c ->
                        if (i > 0) Divisor()
                        LinhaCorrida(c, Corridas.classificar(c, config))
                    }
                }
            }
        }
    }
}

@Composable
fun LinhaIcone(icone: ImageVector, titulo: String, valor: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icone, null, tint = Cor.texto2, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(titulo, color = Cor.texto2, modifier = Modifier.weight(1f))
        Text(valor, color = Cor.texto, fontWeight = FontWeight.SemiBold)
    }
}
