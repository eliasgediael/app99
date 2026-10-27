package com.elias.app99

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import java.time.LocalDate

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        Notificador.canais(this)
        val faltando = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) faltando.add(Manifest.permission.POST_NOTIFICATIONS)
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            faltando.add(Manifest.permission.ACCESS_FINE_LOCATION)
            faltando.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (faltando.isNotEmpty()) requestPermissions(faltando.toTypedArray(), 1)
        setContent { ApexTema { App() } }
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

/** Telas que abrem por cima das abas. */
sealed class Detalhe {
    object Configuracoes : Detalhe()
    object Preferencias : Detalhe()
    object Linha : Detalhe()
    data class MeuDia(val data: LocalDate) : Detalhe()
}

/** Ações do turno, usadas por qualquer tela. */
class AcoesTurno(val iniciar: () -> Unit, val pausar: () -> Unit, val retomar: () -> Unit, val encerrar: () -> Unit)

fun comandoServico(ctx: Context, acao: String) {
    ctx.startService(Intent(ctx, CapturaService::class.java).setAction(acao))
}

/** Corridas, turnos e dias, atualizados quando a leitura grava algo. */
@Composable
fun lembrarPainel(): Painel {
    val ctx = LocalContext.current
    val diario = remember { Diario.get(ctx) }
    val eventos by diario.eventosFlow.collectAsState()
    val dias by diario.diasFlow.collectAsState()
    val turnos by remember { TurnoStore.get(ctx) }.turnos.collectAsState()
    val corridas = remember(eventos) { Corridas.de(eventos) }
    return remember(corridas, turnos, dias) {
        Painel(corridas, turnos, dias, turnos.associate { it.id to Rastro.de(ctx, it) })
    }
}

/** Relógio que anda a cada 30 s (tempo do turno, R$/h). */
@Composable
fun lembrarAgora(): Long {
    var agora by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            agora = System.currentTimeMillis()
        }
    }
    return agora
}

private data class Aba(val nome: String, val icone: ImageVector)

private val abas = listOf(
    Aba("Turno", Icons.Rounded.Home),
    Aba("Dias", Icons.Rounded.CalendarMonth),
    Aba("Mapa", Icons.Rounded.Map),
    Aba("Análises", Icons.Rounded.BarChart),
)

@Composable
fun App() {
    val ctx = LocalContext.current
    var aba by rememberSaveable { mutableIntStateOf(0) }
    val pilha = remember { mutableStateListOf<Detalhe>() }
    BackHandler(enabled = pilha.isNotEmpty()) { pilha.removeAt(pilha.lastIndex) }

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
    var pedirAcessibilidade by remember { mutableStateOf(false) }
    val acoes = remember {
        AcoesTurno(
            iniciar = {
                if (Ajustes.modoLeitura(ctx) == LeituraAcessibilidade.MODO_GRAVACAO) {
                    val mpm = ctx.getSystemService(MediaProjectionManager::class.java)
                    pedirCaptura.launch(mpm.createScreenCaptureIntent())
                } else if (LeituraAcessibilidade.ativa(ctx)) {
                    ContextCompat.startForegroundService(
                        ctx, Intent(ctx, CapturaService::class.java).setAction(CapturaService.ACAO_INICIAR)
                    )
                } else {
                    pedirAcessibilidade = true
                }
            },
            pausar = { comandoServico(ctx, CapturaService.ACAO_PAUSAR) },
            retomar = { comandoServico(ctx, CapturaService.ACAO_RETOMAR) },
            encerrar = { comandoServico(ctx, CapturaService.ACAO_PARAR) }
        )
    }
    val abrir: (Detalhe) -> Unit = { pilha.add(it) }
    val voltar: () -> Unit = { if (pilha.isNotEmpty()) pilha.removeAt(pilha.lastIndex) }

    if (pedirAcessibilidade) DialogoAcessibilidade { pedirAcessibilidade = false }

    val topo = pilha.lastOrNull()
    if (topo != null) {
        Box(Modifier.fillMaxSize().background(Cor.fundo)) {
            when (topo) {
                Detalhe.Configuracoes -> TelaConfiguracoes(voltar, abrir)
                Detalhe.Preferencias -> TelaPreferencias(voltar)
                Detalhe.Linha -> TelaLinha(voltar)
                is Detalhe.MeuDia -> TelaMeuDia(topo.data, voltar) { pilha.clear(); aba = 3 }
            }
        }
        return
    }

    Scaffold(
        containerColor = Cor.fundo,
        bottomBar = {
            NavigationBar(containerColor = Cor.cartao) {
                abas.forEachIndexed { i, a ->
                    NavigationBarItem(
                        selected = aba == i, onClick = { aba = i },
                        icon = { Icon(a.icone, a.nome) }, label = { Text(a.nome) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Cor.azul, selectedTextColor = Cor.azul,
                            indicatorColor = Cor.azul.copy(alpha = 0.14f),
                            unselectedIconColor = Cor.texto2, unselectedTextColor = Cor.texto2
                        )
                    )
                }
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (aba) {
                0 -> TelaTurno(acoes, abrir) { aba = 1 }
                1 -> TelaDias(abrir)
                2 -> TelaMapa(abrir)
                else -> TelaAnalises(abrir)
            }
        }
    }
}

/** Primeira vez: ligar o Apex em Acessibilidade (o Android não deixa o app ligar sozinho). */
@Composable
fun DialogoAcessibilidade(fechar: () -> Unit) {
    val ctx = LocalContext.current
    androidx.compose.material3.AlertDialog(
        onDismissRequest = fechar,
        containerColor = Cor.cartao,
        title = { Text("Ligar a leitura da 99", color = Cor.texto) },
        text = {
            Text(
                "1. Toque em Abrir acessibilidade.\n" +
                    "2. Em Apps instalados, abra Apex e ative.\n\n" +
                    "Se aparecer \"configuração restrita\": toque em Tela do app, depois ⋮ (canto de cima) → " +
                    "Permitir configurações restritas, e volte ao passo 1.",
                color = Cor.texto2
            )
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = {
                ctx.startActivity(
                    Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                fechar()
            }) { Text("Abrir acessibilidade", color = Cor.azul) }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = {
                ctx.startActivity(
                    Intent(
                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.parse("package:${ctx.packageName}")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }) { Text("Tela do app", color = Cor.texto2) }
        }
    )
}
