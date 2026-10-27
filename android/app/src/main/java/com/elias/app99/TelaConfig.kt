package com.elias.app99

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Campo numérico editável guardado nos Ajustes. */
private data class Campo(val chave: String, val titulo: String, val padrao: Double, val formato: (Double) -> String)

@Composable
private fun LinhaCampo(campo: Campo, versao: Int, aoMudar: () -> Unit) {
    val ctx = LocalContext.current
    var editando by remember { mutableStateOf(false) }
    val valor = remember(versao) { Ajustes.valor(ctx, campo.chave, campo.padrao) }
    LinhaValor(campo.titulo, campo.formato(valor)) { editando = true }
    if (editando) {
        DialogoNumero(campo.titulo, valor, { Ajustes.salvar(ctx, campo.chave, it); aoMudar() }) { editando = false }
    }
}

private fun reaisOuDesligado(v: Double) = if (v > 0) Formato.reais(v) else "Desligado"

@Composable
fun TelaConfiguracoes(voltar: () -> Unit, abrir: (Detalhe) -> Unit) {
    val ctx = LocalContext.current
    val padrao = ConfigMoto()
    var versao by remember { mutableIntStateOf(0) }
    var sobreposicao by remember { mutableStateOf(Ajustes.chave(ctx, "overlay", true)) }
    var bolha by remember { mutableStateOf(Ajustes.chave(ctx, "bolha", true)) }
    var notificacoes by remember { mutableStateOf(Ajustes.chave(ctx, "notificacoes", true)) }
    var bairros by remember { mutableStateOf(Ajustes.chave(ctx, "bairros", false)) }

    fun pedirSobreposicao() {
        if (!Settings.canDrawOverlays(ctx)) {
            ctx.startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    Column(Modifier.fillMaxSize()) {
        BarraTopo("Configurações", voltar)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Cartao(espaco = 12.dp) {
                LinhaChave("Aviso sobre o 99Pop", "Mostra a análise de cada oferta por cima", Icons.Rounded.Layers,
                    Cor.azul, sobreposicao) {
                    sobreposicao = it; Ajustes.definirChave(ctx, "overlay", it)
                    if (it) pedirSobreposicao()
                }
                Divisor()
                LinhaChave("Bolha flutuante", "Mostra os ganhos do dia", Icons.Rounded.Add, Cor.verde, bolha) {
                    bolha = it; Ajustes.definirChave(ctx, "bolha", it)
                    if (it) pedirSobreposicao()
                }
                Divisor()
                LinhaChave("Notificações", "Alerta de corrida boa, aceitável ou ruim",
                    Icons.Rounded.NotificationsActive, Cor.verde, notificacoes) {
                    notificacoes = it; Ajustes.definirChave(ctx, "notificacoes", it)
                }
                Divisor()
                LinhaChave("Identificar bairros", "Envia ao serviço de mapas o centro de cada área",
                    null, Cor.azul, bairros) {
                    bairros = it; Ajustes.definirChave(ctx, "bairros", it)
                }
            }

            Cartao(espaco = 12.dp) {
                RotuloSecao("Ver o aviso (exemplo)")
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Veredito.entries.forEach { v ->
                        Text(
                            v.curto, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(v.cor)
                                .clickable {
                                    if (Sobreposicao.permitido(ctx)) Sobreposicao.testar(ctx, v) else pedirSobreposicao()
                                }.padding(vertical = 10.dp)
                        )
                    }
                }
            }

            Cartao(espaco = 12.dp) {
                RotuloSecao("Critérios de análise")
                LinhaCampo(Campo("lucroMinimo", "Lucro mínimo por corrida", padrao.lucroMinimo, ::reaisOuDesligado), versao) { versao++ }
                Divisor()
                LinhaCampo(Campo("minimoPorKm", "Mínimo por km", padrao.minimoPorKm) { Formato.reais(it) }, versao) { versao++ }
                Divisor()
                LinhaCampo(Campo("bomPorKm", "Corrida boa a partir de (por km)", padrao.bomPorKm) { Formato.reais(it) }, versao) { versao++ }
                Divisor()
                LinhaCampo(Campo("notaMinima", "Avaliação mínima", padrao.notaMinima) { Formato.nota(it) }, versao) { versao++ }
            }

            Cartao(espaco = 12.dp) {
                LinhaValor("Preferências", "") { abrir(Detalhe.Preferencias) }
                Divisor()
                LinhaValor("Linha do tempo técnica", "") { abrir(Detalhe.Linha) }
                Divisor()
                LinhaValor("Não otimizar bateria", "") {
                    val pm = ctx.getSystemService(PowerManager::class.java)
                    if (!pm.isIgnoringBatteryOptimizations(ctx.packageName)) {
                        ctx.startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}"))
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
fun TelaPreferencias(voltar: () -> Unit) {
    val ctx = LocalContext.current
    val padrao = ConfigMoto()
    var versao by remember { mutableIntStateOf(0) }
    var voz by remember { mutableStateOf(Ajustes.vozLigada(ctx)) }

    Column(Modifier.fillMaxSize()) {
        BarraTopo("Preferências", voltar)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Cartao(espaco = 12.dp) {
                LinhaValor("Tipo de veículo", "Moto", aoTocar = null)
                Divisor()
                LinhaCampo(Campo("custoPorKm", "Custo por km", padrao.custoPorKm) { Formato.reais(it) }, versao) { versao++ }
                Text("Combustível + manutenção", color = Cor.texto2, fontSize = 12.sp)
                Divisor()
                LinhaCampo(Campo("alertaBuscaKm", "Aviso de busca longa", padrao.alertaBuscaKm) { Formato.km(it) }, versao) { versao++ }
                Divisor()
                LinhaCampo(Campo("metaDiaria", "Meta diária", 0.0, ::reaisOuDesligado), versao) { versao++ }
            }
            Cartao(espaco = 12.dp) {
                LinhaChave("Som de alerta", "Fala o resultado da oferta", null, Cor.azul, voz) {
                    voz = it; Ajustes.definirVoz(ctx, it)
                }
                Divisor()
                LinhaCampo(Campo("velocidadeFala", "Velocidade da voz", 1.0) { Formato.numero(it) + "×" }, versao) { versao++ }
                Divisor()
                LinhaValor("Tema do app", "Escuro", aoTocar = null)
            }
        }
    }
}

private val formatoLinha = DateTimeFormatter.ofPattern("dd/MM HH:mm:ss")

/** Eventos crus da leitura (diagnóstico). */
@Composable
fun TelaLinha(voltar: () -> Unit) {
    val ctx = LocalContext.current
    val eventos by remember { Diario.get(ctx) }.eventosFlow.collectAsState()
    Column(Modifier.fillMaxSize()) {
        BarraTopo("Linha do tempo técnica", voltar)
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (eventos.isEmpty()) item { EstadoVazio("Sem eventos") }
            items(eventos.takeLast(300).asReversed()) { e ->
                Cartao(espaco = 12.dp) {
                    val hora = Instant.ofEpochSecond(e.em).atZone(ZoneId.systemDefault()).format(formatoLinha)
                    Text("$hora · ${e.tipo.nome}", color = Cor.texto, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    e.estadoNovo?.let { novo ->
                        val conf = e.confianca?.let { " · ${it.nome}" } ?: ""
                        Text("${e.estadoAnterior?.nome ?: "-"} → ${novo.nome}$conf", color = Cor.texto2, fontSize = 12.sp)
                    }
                    if (e.valorCent > 0) Text(Formato.reais(e.valorCent / 100.0), color = Cor.texto2, fontSize = 12.sp)
                    val texto = e.motivo.texto(e.extra)
                    if (texto.isNotEmpty()) Text(texto, color = Cor.texto2, fontSize = 12.sp, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}
