package com.blaineam.haven.core

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/**
 * Records a short voice message to an m4a/AAC temp file (parity with iOS AudioRecorder). The bytes
 * are treated like any other media — sealed E2E and sent as an `aud_` ref. Needs RECORD_AUDIO.
 */
class AudioRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    var outputFile: File? = null
        private set

    fun start() {
        val f = File(context.cacheDir, "voice_${System.nanoTime()}.m4a")
        outputFile = f
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context)
        else @Suppress("DEPRECATION") MediaRecorder()
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioSamplingRate(44_100)
        r.setAudioEncodingBitRate(64_000)
        r.setOutputFile(f.absolutePath)
        runCatching { r.prepare(); r.start() }
        recorder = r
    }

    /** Stop + return the recorded file (or null on failure / too-short clip). */
    fun stop(): File? {
        val r = recorder ?: return null
        recorder = null
        runCatching { r.stop() }
        runCatching { r.release() }
        val f = outputFile
        return if (f != null && f.exists() && f.length() > 0) f else null
    }

    fun cancel() {
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        outputFile?.delete()
        outputFile = null
    }
}
