package com.blaineam.haven.ui

import android.annotation.SuppressLint
import android.content.ContentValues
import android.provider.MediaStore
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
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.blaineam.haven.core.LocalMedia
import com.blaineam.haven.core.readVideoBytes
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

/** A captured story (a stored media ref + whether it's video), handed to the editor. */
private data class StoryDraft(val ref: String, val isVideo: Boolean)

/**
 * In-app story camera: live preview, TAP = photo, HOLD = video (release to stop), flip. After
 * capture it hands off to [StoryEditor] for a caption + song, then posts. Proper recording
 * lifecycle (start on hold, stop on release, one recording at a time) — fixes the prior crash.
 */
@SuppressLint("MissingPermission")
@Composable
fun StoryCameraScreen(onClose: () -> Unit) {
    var draft by remember { mutableStateOf<StoryDraft?>(null) }
    val d = draft
    if (d != null) {
        StoryEditor(ref = d.ref, isVideo = d.isVideo, onClose = onClose)
        return
    }

    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    var lensFront by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Tap for photo · hold for video") }
    var isRecording by remember { mutableStateOf(false) }
    val imageCapture = remember { ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }
    val videoCapture = remember { VideoCapture.withOutput(Recorder.Builder().build()) }
    val recordingRef = remember { arrayOfNulls<Recording>(1) }

    fun takePhoto() {
        status = "Capturing…"
        imageCapture.takePicture(ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: androidx.camera.core.ImageProxy) {
                    val bytes = runCatching {
                        val buf = image.planes[0].buffer
                        ByteArray(buf.remaining()).also { buf.get(it) }
                    }.getOrNull()
                    image.close()
                    if (bytes != null) draft = StoryDraft(LocalMedia.store(DEFAULT_CIRCLE, bytes), false)
                    else status = "Couldn't capture"
                }
                override fun onError(e: ImageCaptureException) { status = "Capture failed" }
            })
    }

    fun startVideo() {
        if (recordingRef[0] != null) return
        status = "Recording…"; isRecording = true
        val name = "haven_${System.nanoTime()}"
        val opts = MediaStoreOutputOptions.Builder(
            context.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        ).setContentValues(ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
        }).build()
        recordingRef[0] = videoCapture.output.prepareRecording(context, opts)
            .start(ContextCompat.getMainExecutor(context)) { ev ->
                if (ev is VideoRecordEvent.Finalize) {
                    isRecording = false
                    recordingRef[0] = null
                    if (!ev.hasError()) {
                        val bytes = readVideoBytes(context, ev.outputResults.outputUri)
                        if (bytes != null) draft = StoryDraft(LocalMedia.store(DEFAULT_CIRCLE, bytes, isVideo = true), true)
                        else status = "Couldn't read video"
                    } else status = "Recording failed"
                }
            }
    }

    fun stopVideo() {
        runCatching { recordingRef[0]?.stop() }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { PreviewView(it) },
            update = { previewView ->
                val future = ProcessCameraProvider.getInstance(context)
                future.addListener({
                    val provider = future.get()
                    val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                    val selector = if (lensFront) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                    runCatching {
                        provider.unbindAll()
                        provider.bindToLifecycle(lifecycleOwner, selector, preview, imageCapture, videoCapture)
                    }.onFailure {
                        // Some older cameras can't bind photo+video together — fall back to photo-only.
                        runCatching { provider.bindToLifecycle(lifecycleOwner, selector, preview, imageCapture) }
                    }
                }, ContextCompat.getMainExecutor(context))
            },
        )

        Box(Modifier.align(Alignment.TopStart).padding(16.dp).size(40.dp).clip(CircleShape)
            .pointerInput(Unit) { detectClose(onClose) }, contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Close", tint = Color.White)
        }
        Box(Modifier.align(Alignment.TopEnd).padding(16.dp).size(40.dp).clip(CircleShape)
            .pointerInput(Unit) { detectClose { lensFront = !lensFront } }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Cameraswitch, "Flip camera", tint = Color.White)
        }

        Text(status, color = Color.White, fontSize = 13.sp,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 150.dp))

        // Shutter: tap = photo, press-and-hold = video (release to stop).
        Box(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 56.dp).size(78.dp).clip(CircleShape)
                .border(4.dp, if (isRecording) Color(0xFFEF4444) else Color.White, CircleShape)
                .background(if (isRecording) Color(0xFFEF4444).copy(alpha = 0.5f) else Color.White.copy(alpha = 0.25f))
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown()
                        val held = arrayOf(false)
                        val job = scope.launch { delay(350); held[0] = true; startVideo() }
                        waitForUpOrCancellation()
                        job.cancel()
                        if (held[0]) stopVideo() else takePhoto()
                    }
                },
        )
    }
}

/** A tap detector for the small icon buttons (so they don't interfere with the shutter gesture). */
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.detectClose(onTap: () -> Unit) {
    awaitEachGesture {
        awaitFirstDown()
        if (waitForUpOrCancellation() != null) onTap()
    }
}

/**
 * The story editor (parity with the iOS story composer): the captured photo/video full-screen, a
 * caption you type over it, an optional song, then Share to story.
 */
@Composable
fun StoryEditor(ref: String, isVideo: Boolean, onClose: () -> Unit) {
    var caption by remember { mutableStateOf("") }
    var music by remember { mutableStateOf<uniffi.haven_ffi.TrackRefFfi?>(null) }
    var pickSong by remember { mutableStateOf(false) }

    if (pickSong) {
        MusicSearchSheet(onPick = { music = it; pickSong = false }, onDismiss = { pickSong = false })
        return
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (isVideo) VideoTile(DEFAULT_CIRCLE, ref, Modifier.fillMaxSize())
        else MediaImage(DEFAULT_CIRCLE, ref, Modifier.fillMaxSize())

        // Top: back.
        Box(Modifier.align(Alignment.TopStart).padding(16.dp).size(40.dp).clip(CircleShape)
            .clickable { onClose() }, contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White)
        }

        // Caption overlaid on the media.
        androidx.compose.material3.OutlinedTextField(
            value = caption, onValueChange = { caption = it },
            placeholder = { Text("Add a caption…", color = Color.White.copy(alpha = 0.7f)) },
            modifier = Modifier.align(Alignment.Center).padding(24.dp).fillMaxWidth(),
            colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color.White, unfocusedBorderColor = Color.White.copy(alpha = 0.4f),
                focusedTextColor = Color.White, unfocusedTextColor = Color.White, cursorColor = HavenTheme.pink),
        )

        // Song chip (above the controls).
        music?.let { m ->
            Box(Modifier.align(Alignment.BottomCenter).padding(start = 16.dp, end = 16.dp, bottom = 96.dp)) {
                MusicChip(m)
            }
        }

        // Bottom controls: add song + Share.
        Row(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 32.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(if (music == null) "♪ Add song" else "♪ Change song", color = Color.White, fontSize = 14.sp,
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.18f))
                    .clickable { pickSong = true }.padding(horizontal = 16.dp, vertical = 10.dp))
            Text("Share to story", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clip(CircleShape).background(HavenTheme.brandHorizontal)
                    .clickable {
                        com.blaineam.haven.core.HavenNet.postStory(caption.trim(), ref, music)
                        onClose()
                    }.padding(horizontal = 22.dp, vertical = 10.dp))
        }
    }
}
