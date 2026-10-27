package com.elias.app99

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
fun TelaMapa(abrir: (Detalhe) -> Unit) {
    Column(Modifier.fillMaxSize()) {
        BarraTopo("Mapa", null)
        EstadoVazio("Mapa de ganhos em construção")
    }
}
