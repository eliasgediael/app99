package com.elias.app99

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notificador.canais(this)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) { App() }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        Estado.appNaFrente = true
    }

    override fun onStop() {
        super.onStop()
        Estado.appNaFrente = false
    }
}

@Composable
fun App() {
    var aba by remember { mutableIntStateOf(0) }
    val nomes = listOf("🛵" to "Turno", "📅" to "Dias", "🕒" to "Linha", "⚙️" to "Ajustes")
    Scaffold(
        bottomBar = {
            NavigationBar {
                nomes.forEachIndexed { i, (icone, nome) ->
                    NavigationBarItem(
                        selected = aba == i, onClick = { aba = i },
                        icon = { Text(icone, fontSize = 20.sp) }, label = { Text(nome) }
                    )
                }
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            when (aba) {
                0 -> TelaTurno()
                1 -> TelaDias()
                2 -> TelaLinha()
                else -> TelaAjustes()
            }
        }
    }
}

@Composable
fun Linha(rotulo: String, valor: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(rotulo)
        Text(valor, fontWeight = FontWeight.SemiBold)
    }
}

// MARK: Turno

@Composable
fun TelaTurno() {
    val ctx = LocalContext.current
    val diario = remember { Diario.get(ctx) }
    val dias by diario.diasFlow.collectAsState()
    val rodando by Estado.rodando.collectAsState()
    val analise by Estado.ultimaAnalise.collectAsState()
    val hoje = dias.firstOrNull { it.dia == Dia.numero() } ?: Dia(Dia.numero())

    val pedirCaptura = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val dados = r.data
        if (r.resultCode == android.app.Activity.RESULT_OK && dados != null) {
            ContextCompat.startForegroundService(
                ctx,
                Intent(ctx, CapturaService::class.java)
                    .putExtra(CapturaService.EXTRA_CODE, r.resultCode)
                    .putExtra(CapturaService.EXTRA_DATA, dados)
            )
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Apex", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Button(
            onClick = {
                if (rodando) {
                    ctx.startService(Intent(ctx, CapturaService::class.java).setAction(CapturaService.ACAO_PARAR))
                } else {
                    val mpm = ctx.getSystemService(MediaProjectionManager::class.java)
                    pedirCaptura.launch(mpm.createScreenCaptureIntent())
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text(if (rodando) "Encerrar turno" else "Iniciar turno") }
        Text(
            if (rodando) "Lendo a tela. Abra a 99." else "Parado. Ao iniciar, o Android pede permissão para gravar a tela.",
            fontSize = 13.sp
        )

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Hoje", fontWeight = FontWeight.Bold)
                Linha("Faturado (confirmadas)", Formato.reais(hoje.faturado))
                Linha("Lucro", Formato.reais(hoje.lucro))
                Linha("Corridas", "${hoje.corridas} de ${hoje.ofertas} ofertas")
                Linha("Km", Formato.km(hoje.km))
                hoje.porKm?.let { Linha("Por km", Formato.reais(it)) }
                hoje.lucroPorHora?.let { Linha("Lucro por hora", Formato.reais(it)) }
                Linha("Tempo ligado", "%.1f h".format(java.util.Locale.US, hoje.horas).replace('.', ','))
                if (hoje.estimadas > 0) {
                    Linha("Estimadas (fora do total)", "${hoje.estimadas} · ${Formato.reais(hoje.estimado)}")
                }
            }
        }

        analise?.let { a ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Última oferta: ${a.veredito.emoji} ${a.veredito.falado}", fontWeight = FontWeight.Bold)
                    Linha("Valor", Formato.reais(a.oferta.valor))
                    Linha("Lucro", Formato.reais(a.lucro))
                    Linha("Por km", Formato.reais(a.ganhoPorKm))
                    Linha("Distância total", Formato.km(a.kmTotal))
                    Linha("Busca", Formato.km(a.oferta.kmAtePassageiro))
                    a.oferta.notaPassageiro?.let { Linha("Nota", Formato.nota(it)) }
                    a.ganhoPorHora?.let { Linha("Lucro por hora", Formato.reais(it)) }
                }
            }
        }
    }
}

// MARK: Dias

@Composable
fun TelaDias() {
    val ctx = LocalContext.current
    val dias by remember { Diario.get(ctx) }.diasFlow.collectAsState()
    val formato = DateTimeFormatter.ofPattern("dd/MM/yyyy")
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        if (dias.isEmpty()) item { Text("Nenhum turno ainda.") }
        items(dias.asReversed()) { d ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(LocalDate.ofEpochDay(d.dia.toLong()).format(formato), fontWeight = FontWeight.Bold)
                    Linha("Faturado", Formato.reais(d.faturado))
                    Linha("Lucro", Formato.reais(d.lucro))
                    Linha("Corridas", "${d.corridas} de ${d.ofertas} ofertas")
                    Linha("Km", Formato.km(d.km))
                    if (d.estimadas > 0) Linha("Estimadas", "${d.estimadas} · ${Formato.reais(d.estimado)}")
                }
            }
        }
    }
}

// MARK: Linha do tempo

@Composable
fun TelaLinha() {
    val ctx = LocalContext.current
    val eventos by remember { Diario.get(ctx) }.eventosFlow.collectAsState()
    val formato = DateTimeFormatter.ofPattern("dd/MM HH:mm:ss")
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        if (eventos.isEmpty()) item { Text("Sem eventos ainda.") }
        items(eventos.takeLast(300).asReversed()) { e ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    val hora = Instant.ofEpochSecond(e.em).atZone(ZoneId.systemDefault()).format(formato)
                    Text("$hora · ${e.tipo.nome}", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    val estado = e.estadoNovo
                    if (estado != null) {
                        val conf = e.confianca?.let { " · ${it.nome}" } ?: ""
                        Text("${e.estadoAnterior?.nome ?: "-"} → ${estado.nome}$conf", fontSize = 12.sp)
                    }
                    if (e.valorCent > 0) Text(Formato.reais(e.valorCent / 100.0), fontSize = 12.sp)
                    val texto = e.motivo.texto(e.extra)
                    if (texto.isNotEmpty()) Text(texto, fontSize = 12.sp)
                }
            }
        }
    }
}

// MARK: Ajustes

@Composable
fun CampoNumero(rotulo: String, chave: String, padrao: Double) {
    val ctx = LocalContext.current
    var texto by remember { mutableStateOf(Ajustes.texto(ctx, chave, padrao)) }
    OutlinedTextField(
        value = texto,
        onValueChange = { novo ->
            texto = novo
            novo.replace(',', '.').toDoubleOrNull()?.let { Ajustes.salvar(ctx, chave, it) }
        },
        label = { Text(rotulo) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.fillMaxWidth()
    )
}

@Composable
fun TelaAjustes() {
    val ctx = LocalContext.current
    val d = ConfigMoto()
    var voz by remember { mutableStateOf(Ajustes.vozLigada(ctx)) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Configuração da moto", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        CampoNumero("Custo por km (R$)", "custoPorKm", d.custoPorKm)
        CampoNumero("Mínimo por km (R$) — abaixo disso, recusa", "minimoPorKm", d.minimoPorKm)
        CampoNumero("Bom por km (R$) — acima disso, corrida boa", "bomPorKm", d.bomPorKm)
        CampoNumero("Alerta de busca longa (km)", "alertaBuscaKm", d.alertaBuscaKm)
        CampoNumero("Nota mínima do passageiro", "notaMinima", d.notaMinima)
        CampoNumero("Velocidade da voz (1 = normal)", "velocidadeFala", 1.0)

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Falar resultado")
            Switch(checked = voz, onCheckedChange = { voz = it; Ajustes.definirVoz(ctx, it) })
        }

        OutlinedButton(
            onClick = {
                val pm = ctx.getSystemService(PowerManager::class.java)
                if (!pm.isIgnoringBatteryOptimizations(ctx.packageName)) {
                    ctx.startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}"))
                    )
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Não otimizar bateria (evita o Android matar a leitura)") }

        OutlinedButton(
            onClick = { Diario.get(ctx).zerarHoje() },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Zerar números de hoje") }
    }
}
