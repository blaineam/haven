package com.blaineam.haven.ui

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.ImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** Render a string into a QR [ImageBitmap] (white-on-transparent so it sits on the dark card). */
@Composable
fun rememberQr(content: String, size: Int = 720): ImageBitmap? = remember(content, size) {
    runCatching { encodeQr(content, size) }.getOrNull()?.asImageBitmap()
}

fun encodeQr(content: String, size: Int): Bitmap {
    val hints = mapOf(
        EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
        EncodeHintType.MARGIN to 1,
    )
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val on = 0xFFFFFFFF.toInt()
    val off = 0x00000000
    for (y in 0 until size) {
        for (x in 0 until size) {
            bmp.setPixel(x, y, if (matrix[x, y]) on else off)
        }
    }
    return bmp
}
