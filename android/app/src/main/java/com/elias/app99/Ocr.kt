package com.elias.app99

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlin.math.roundToInt

object Ocr {
    private val reconhecedor by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** Linhas na ordem de leitura (cima → baixo, esquerda → direita). */
    fun ordenar(texto: Text, altura: Int): List<String> {
        val tolerancia = maxOf(1f, altura * 0.01f)
        return texto.textBlocks.flatMap { it.lines }
            .filter { it.boundingBox != null }
            .sortedWith(
                compareBy<Text.Line>({ (it.boundingBox!!.exactCenterY() / tolerancia).roundToInt() },
                    { it.boundingBox!!.left })
            )
            .map { it.text }
    }

    /** Lê o texto de uma imagem (bloqueia: chamar fora da thread da tela). */
    fun ler(bitmap: Bitmap): List<String> =
        ordenar(Tasks.await(reconhecedor.process(InputImage.fromBitmap(bitmap, 0))), bitmap.height)

    fun abrir(ctx: Context, uri: Uri): Bitmap =
        if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(ctx.contentResolver, uri)) { d, _, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            @Suppress("DEPRECATION") MediaStore.Images.Media.getBitmap(ctx.contentResolver, uri)
        }
}

/** Resultado do teste com print. */
data class TestePrint(val linhas: List<String>, val analise: AnaliseCorrida?)

fun testarPrint(ctx: Context, uri: Uri): TestePrint {
    val linhas = Ocr.ler(Ocr.abrir(ctx, uri))
    val oferta = ParserOferta99.extrair(linhas)
    val analise = oferta?.let { CalculadoraCorrida(Ajustes.config(ctx)).analisar(it) }
    return TestePrint(linhas, analise)
}
