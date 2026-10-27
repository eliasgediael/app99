package com.elias.app99

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Paleta do Apex: escuro, azul como cor principal, verde/âmbar/vermelho só para o resultado. */
object Cor {
    val fundo = Color(0xFF0D0F12)
    val cartao = Color(0xFF16191E)
    val cartaoAlto = Color(0xFF1E2229)
    val borda = Color(0xFF232730)
    val texto = Color(0xFFFFFFFF)
    val texto2 = Color(0xFF9AA3AE)
    val texto3 = Color(0xFF5E6672)
    val azul = Color(0xFF3B82F6)
    val verde = Color(0xFF10B981)
    val ambar = Color(0xFFF5B83D)
    val vermelho = Color(0xFFEF4444)
    val amarelo99 = Color(0xFFFFD43B)
}

val Veredito.cor: Color
    get() = when (this) {
        Veredito.BOA -> Cor.verde
        Veredito.ACEITAVEL -> Cor.ambar
        Veredito.RUIM -> Cor.vermelho
    }

/** Nome na tela (a voz continua falando "Recusa"). */
val Veredito.titulo: String
    get() = when (this) {
        Veredito.BOA -> "Corrida boa"
        Veredito.ACEITAVEL -> "Corrida aceitável"
        Veredito.RUIM -> "Corrida ruim"
    }

val Veredito.curto: String
    get() = when (this) {
        Veredito.BOA -> "Boa"
        Veredito.ACEITAVEL -> "Aceitável"
        Veredito.RUIM -> "Ruim"
    }

private val esquema = darkColorScheme(
    primary = Cor.azul,
    onPrimary = Color.White,
    secondary = Cor.verde,
    tertiary = Cor.ambar,
    error = Cor.vermelho,
    background = Cor.fundo,
    onBackground = Cor.texto,
    surface = Cor.cartao,
    onSurface = Cor.texto,
    surfaceVariant = Cor.cartaoAlto,
    onSurfaceVariant = Cor.texto2,
    outline = Cor.borda,
    outlineVariant = Cor.borda,
    surfaceContainer = Cor.cartao,
)

private val tipos = Typography(
    displayLarge = TextStyle(fontSize = 44.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 14.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium),
)

@Composable
fun ApexTema(conteudo: @Composable () -> Unit) {
    MaterialTheme(colorScheme = esquema, typography = tipos, content = conteudo)
}
