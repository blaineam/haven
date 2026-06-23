package com.blaineam.haven.ui

import android.annotation.SuppressLint
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.blaineam.haven.core.DEFAULT_CIRCLE
import com.blaineam.haven.core.HavenNet
import com.blaineam.haven.core.LocalMedia
import com.blaineam.haven.core.readVideoBytes
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * A real in-app story camera (CameraX): live preview, TAP for a photo, HOLD for video, flip
 * camera — replacing the system picker for stories. On capture it stores the media and posts it
 * as a 24h story, then closes.
 */
@SuppressLint("MissingPermission")
@Composable
fun StoryCameraScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    var lensFront by remember { mutableStateOf(false) }
    var recording: Recording? by remember { mutableStateOf(null) }
    var status by remember { mutableStateOf("Tap for photo · hold for video") }
    val imageCapture = remember { ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }
    val videoCapture = remember { VideoCapture.withOutput(Recorder.Builder().build()) }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx -> PreviewView(ctx) },
            update = { previewView ->
                val future = ProcessCameraProvider.getInstance(context)
                future.addListener({
                    val provider = future.get()
                    val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                    val selector = if (lensFront) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                    runCatching {
                        provider.unbindAll()
                        provider.bindToLifecycle(lifecycleOwner, selector, preview, imageCapture, videoCapture)
                    }
                }, ContextCompat.getMainExecutor(context))
            },
        )

        // Top bar.
        Box(Modifier.align(Alignment.TopStart).padding(16.dp).size(40.dp).clip(CircleShape).clickable { onClose() },
            contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Close", tint = Color.White)
        }
        Box(Modifier.align(Alignment.TopEnd).padding(16.dp).size(40.dp).clip(CircleShape).clickable { lensFront = !lensFront },
            contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Cameraswitch, "Flip camera", tint = Color.White)
        }

        Text(status, color = Color.White, fontSize = 13.sp,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 150.dp))

        // Shutter: tap = photo, long-press = record video.
        val isRecording = recording != null
        Box(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 56.dp).size(78.dp)
                .clip(CircleShape)
                .border(4.dp, if (isRecording) Color(0xFFEF4444) else Color.White, CircleShape)
                .background(if (isRecording) Color(0xFFEF4444).copy(alpha = 0.5f) else Color.White.copy(alpha = 0.25f))
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = {
                            status = "Capturing…"
                            imageCapture.takePicture(executor, object : ImageCapture.OnImageCapturedCallback() {
                                override fun onCaptureSuccess(image: androidx.camera.core.ImageProxy) {
                                    val bytes = jpegBytes(image); image.close()
                                    if (bytes != null) {
                                        val ref = LocalMedia.store(DEFAULT_CIRCLE, bytes)
                                        HavenNet.postStory("", ref)
                                    }
                                    previewPost(onClose)
                                }
                                override fun onError(e: ImageCaptureException) { status = "Capture failed" }
                            })
                        },
                        onLongPress = {
                            // Record to MediaStore, then read back + post (CameraX needs a sink).
                            status = "Recording…"
                            val name = "haven_${System.nanoTime()}"
                            val opts = MediaStoreOutputOptions.Builder(
                                context.contentResolver,
                                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            ).setContentValues(android.content.ContentValues().apply {
                                put(android.provider.MediaStore.Video.Media.DISPLAY_NAME, name)
                            }).build()
                            recording = videoCapture.output.prepareRecording(context, opts)
                                .start(ContextCompat.getMainExecutor(context)) { ev ->
                                    if (ev is VideoRecordEvent.Finalize) {
                                        val uri = ev.outputResults.outputUri
                                        val bytes = readVideoBytes(context, uri)
                                        if (bytes != null) {
                                            val ref = LocalMedia.store(DEFAULT_CIRCLE, bytes, isVideo = true)
                                            HavenNet.postStory("", ref)
                                        }
                                        previewPost(onClose)
                                    }
                                }
                        },
                    )
                },
        )
    }
}

private fun previewPost(onClose: () -> Unit) {
    onClose()
}

/** Pull JPEG bytes out of an ImageProxy (CameraX delivers JPEG for image capture). */
private fun jpegBytes(image: androidx.camera.core.ImageProxy): ByteArray? = runCatching {
    val buffer = image.planes[0].buffer
    ByteArray(buffer.remaining()).also { buffer.get(it) }
}.getOrNull()
