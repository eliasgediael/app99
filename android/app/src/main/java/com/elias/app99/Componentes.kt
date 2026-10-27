package com.elias.app99

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun Cartao(
    modifier: Modifier = Modifier,
    espaco: Dp = 16.dp,
    conteudo: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Cor.cartao)
            .border(1.dp, Cor.borda, RoundedCornerShape(18.dp))
            .padding(espaco),
        content = conteudo
    )
}

@Composable
fun RotuloSecao(texto: String, modifier: Modifier = Modifier) {
    Text(texto, modifier = modifier, color = Cor.texto2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
}

/** Pílula com bolinha (status do turno). */
@Composable
fun Pilula(texto: String, cor: Color, modifier: Modifier = Modifier) {
    Row(
        modifier
            .clip(RoundedCornerShape(50))
            .background(cor.copy(alpha = 0.16f))
            .border(1.dp, cor.copy(alpha = 0.5f), RoundedCornerShape(50))
            .padding(horizontal = 14.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(cor))
        Spacer(Modifier.width(8.dp))
        Text(texto, color = cor, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Cartão pequeno de métrica: ícone, valor e rótulo. */
@Composable
fun MetricaCartao(icone: ImageVector?, valor: String, rotulo: String, modifier: Modifier = Modifier) {
    Row(
        modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Cor.cartao)
            .border(1.dp, Cor.borda, RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icone != null) {
            Icon(icone, null, tint = Cor.azul, modifier = Modifier.size(26.dp))
            Spacer(Modifier.width(10.dp))
        }
        Column {
            Text(valor, color = Cor.texto, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(rotulo, color = Cor.texto2, fontSize = 12.sp, maxLines = 1)
        }
    }
}

@Composable
fun BarraProgresso(fracao: Float, cor: Color, modifier: Modifier = Modifier, altura: Dp = 8.dp) {
    Box(modifier.fillMaxWidth().height(altura).clip(RoundedCornerShape(50)).background(Cor.cartaoAlto)) {
        Box(
            Modifier.fillMaxWidth(fracao.coerceIn(0f, 1f)).height(altura)
                .clip(RoundedCornerShape(50)).background(cor)
        )
    }
}

/** Seletor segmentado (Hoje | Semana | Mês). */
@Composable
fun <T> Segmentos(opcoes: List<T>, nome: (T) -> String, selecionado: T, aoTrocar: (T) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Cor.cartao)
            .border(1.dp, Cor.borda, RoundedCornerShape(14.dp)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        opcoes.forEach { o ->
            val ativo = o == selecionado
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                    .background(if (ativo) Cor.azul else Color.Transparent)
                    .clickable { aoTrocar(o) }.padding(vertical = 9.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    nome(o), color = if (ativo) Color.White else Cor.texto2,
                    fontSize = 14.sp, fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
fun EstadoVazio(titulo: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(vertical = 36.dp), contentAlignment = Alignment.Center) {
        Text(titulo, color = Cor.texto3, fontSize = 14.sp, textAlign = TextAlign.Center)
    }
}

/** Selo de dados de exemplo: nunca misturar com dado real. */
@Composable
fun SeloDemonstracao(modifier: Modifier = Modifier) {
    Text(
        "DEMONSTRAÇÃO · dados de exemplo",
        modifier = modifier.clip(RoundedCornerShape(50)).background(Cor.ambar.copy(alpha = 0.18f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        color = Cor.ambar, fontSize = 11.sp, fontWeight = FontWeight.Bold
    )
}

// MARK: Linhas de configuração

@Composable
fun LinhaChave(
    titulo: String, subtitulo: String?, icone: ImageVector?, corIcone: Color = Cor.azul,
    ligado: Boolean, aoMudar: (Boolean) -> Unit
) {
    Row(
        Modifier.fillMaxWidth().clickable { aoMudar(!ligado) }.padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icone != null) {
            Box(
                Modifier.size(36.dp).clip(CircleShape).background(corIcone.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) { Icon(icone, null, tint = corIcone, modifier = Modifier.size(20.dp)) }
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(titulo, color = Cor.texto, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            if (subtitulo != null) Text(subtitulo, color = Cor.texto2, fontSize = 12.sp)
        }
        Switch(
            checked = ligado, onCheckedChange = aoMudar,
            colors = SwitchDefaults.colors(checkedTrackColor = Cor.azul, checkedThumbColor = Color.White)
        )
    }
}

@Composable
fun LinhaValor(titulo: String, valor: String, subtitulo: String? = null, aoTocar: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth()
            .then(if (aoTocar != null) Modifier.clickable(onClick = aoTocar) else Modifier)
            .padding(vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(titulo, color = Cor.texto, fontSize = 15.sp)
            if (subtitulo != null) Text(subtitulo, color = Cor.texto2, fontSize = 12.sp)
        }
        Text(valor, color = Cor.texto, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        if (aoTocar != null) {
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Cor.texto3)
        }
    }
}

@Composable
fun Divisor() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Cor.borda))
}

/** Edita um número (aceita vírgula). */
@Composable
fun DialogoNumero(titulo: String, valorInicial: Double, aoSalvar: (Double) -> Unit, aoFechar: () -> Unit) {
    var texto by remember { mutableStateOf(Formato.numero(valorInicial)) }
    val valor = texto.replace(',', '.').toDoubleOrNull()
    AlertDialog(
        onDismissRequest = aoFechar,
        containerColor = Cor.cartao,
        title = { Text(titulo, color = Cor.texto) },
        text = {
            OutlinedTextField(
                value = texto, onValueChange = { texto = it }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
            )
        },
        confirmButton = {
            TextButton(enabled = valor != null && valor >= 0, onClick = { valor?.let(aoSalvar); aoFechar() }) {
                Text("Salvar", color = Cor.azul)
            }
        },
        dismissButton = { TextButton(onClick = aoFechar) { Text("Cancelar", color = Cor.texto2) } }
    )
}

// MARK: Gráficos

data class Barra(val rotulo: String, val valor: Double?, val destaque: Boolean = false)

/**
 * Barras verticais com valor em cima. Barra sem dado (valor null) é hiato: nada é desenhado.
 * Toque numa barra destaca e devolve o índice.
 */
@Composable
fun GraficoBarras(
    barras: List<Barra>, selecionada: Int?, aoTocar: (Int) -> Unit,
    modifier: Modifier = Modifier, altura: Dp = 150.dp
) {
    val maior = barras.mapNotNull { it.valor }.maxOrNull()?.takeIf { it > 0 } ?: 1.0
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth()) {
            barras.forEach { b ->
                Text(
                    b.valor?.let { Formato.inteiro(it) } ?: "",
                    Modifier.weight(1f), color = Cor.texto2, fontSize = 11.sp, textAlign = TextAlign.Center
                )
            }
        }
        Canvas(
            Modifier.fillMaxWidth().height(altura).pointerInput(barras) {
                detectTapGestures { p ->
                    val i = (p.x / (size.width / barras.size)).toInt().coerceIn(0, barras.size - 1)
                    if (barras[i].valor != null) aoTocar(i)
                }
            }
        ) {
            val passo = size.width / barras.size
            val largura = passo * 0.55f
            barras.forEachIndexed { i, b ->
                val v = b.valor ?: return@forEachIndexed
                val h = (size.height * (v / maior)).toFloat().coerceAtLeast(4f)
                val ativo = selecionada == i || (selecionada == null && b.destaque)
                val cor = when {
                    b.destaque -> Cor.verde
                    ativo -> Cor.azul
                    else -> Cor.azul.copy(alpha = 0.75f)
                }
                drawRoundRect(
                    color = if (selecionada != null && !ativo) cor.copy(alpha = 0.35f) else cor,
                    topLeft = Offset(i * passo + (passo - largura) / 2, size.height - h),
                    size = Size(largura, h),
                    cornerRadius = CornerRadius(6.dp.toPx())
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth()) {
            barras.forEachIndexed { i, b ->
                Text(
                    b.rotulo, Modifier.weight(1f),
                    color = if (selecionada == i) Cor.texto else Cor.texto2,
                    fontSize = 12.sp, textAlign = TextAlign.Center
                )
            }
        }
    }
}

data class Fatia(val nome: String, val valor: Double, val cor: Color)

/** Rosca com legenda à direita (Tipos de corrida). */
@Composable
fun Rosca(fatias: List<Fatia>, modifier: Modifier = Modifier) {
    val total = fatias.sumOf { it.valor }.takeIf { it > 0 } ?: return
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(96.dp)) {
            val traco = 18.dp.toPx()
            var inicio = -90f
            fatias.forEach { f ->
                val arco = (f.valor / total * 360).toFloat()
                drawArc(
                    color = f.cor, startAngle = inicio, sweepAngle = (arco - 2f).coerceAtLeast(0.5f),
                    useCenter = false, topLeft = Offset(traco / 2, traco / 2),
                    size = Size(size.width - traco, size.height - traco),
                    style = Stroke(width = traco, cap = StrokeCap.Butt)
                )
                inicio += arco
            }
        }
        Spacer(Modifier.width(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            fatias.forEach { f ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).clip(CircleShape).background(f.cor))
                    Spacer(Modifier.width(8.dp))
                    Text(f.nome, color = Cor.texto, fontSize = 14.sp, modifier = Modifier.width(90.dp))
                    Text(
                        "${Math.round(f.valor / total * 100)}%", color = Cor.texto,
                        fontSize = 14.sp, fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
}
