package com.elias.app99

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.MutableStateFlow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Uma tela da 99 como a acessibilidade entregou (pra descobrir onde está o texto da oferta). */
data class FotoTela(
    val em: Long,
    val pacote: String,
    val evento: String,
    val janelas: Int,
    val linhas: List<String>,
    val lidoComoOferta: Boolean
)

/** Guarda as últimas telas diferentes que a acessibilidade recebeu da 99 (só na memória). */
object DiagnosticoLeitura {
    private const val MAXIMO = 30
    val fotos = MutableStateFlow<List<FotoTela>>(emptyList())
    private var ultimaAssinatura = 0

    @Synchronized fun registrar(f: FotoTela) {
        val assinatura = f.linhas.hashCode()
        if (assinatura == ultimaAssinatura) return
        ultimaAssinatura = assinatura
        fotos.value = (listOf(f) + fotos.value).take(MAXIMO)
    }

    fun limpar() {
        fotos.value = emptyList()
        ultimaAssinatura = 0
    }

    private val hora = DateTimeFormatter.ofPattern("HH:mm:ss")

    fun titulo(f: FotoTela): String =
        "${Instant.ofEpochMilli(f.em).atZone(ZoneId.systemDefault()).format(hora)} · ${f.evento} · " +
            "${f.janelas} janela(s)" + if (f.lidoComoOferta) " · OFERTA LIDA" else ""

    fun texto(): String = fotos.value.joinToString("\n\n") { f ->
        "== ${titulo(f)} · ${f.pacote}\n" + f.linhas.joinToString("\n")
    }
}

@Composable
fun TelaDiagnostico(voltar: () -> Unit) {
    val ctx = LocalContext.current
    val fotos by DiagnosticoLeitura.fotos.collectAsState()
    Column(Modifier.fillMaxSize()) {
        BarraTopo("Diagnóstico da leitura", voltar)
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = {
                    val envio = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, DiagnosticoLeitura.texto())
                    ctx.startActivity(Intent.createChooser(envio, "Compartilhar diagnóstico"))
                },
                enabled = fotos.isNotEmpty(), modifier = Modifier.weight(1f).height(48.dp),
                shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = Cor.azul)
            ) { Text("Compartilhar") }
            OutlinedButton(
                onClick = { DiagnosticoLeitura.limpar() }, modifier = Modifier.weight(1f).height(48.dp),
                shape = RoundedCornerShape(12.dp)
            ) { Text("Limpar", color = Cor.texto) }
        }
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (fotos.isEmpty()) item { EstadoVazio("Nada lido da 99 ainda. Com o turno ativo, abra a 99 e espere uma oferta.") }
            items(fotos) { f ->
                Cartao(espaco = 12.dp) {
                    Text(DiagnosticoLeitura.titulo(f), color = if (f.lidoComoOferta) Cor.verde else Cor.texto,
                        fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Text(f.pacote, color = Cor.texto3, fontSize = 11.sp)
                    Text(
                        f.linhas.joinToString("\n").ifEmpty { "(nenhum texto)" },
                        color = Cor.texto2, fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
            }
        }
    }
}
