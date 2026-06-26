package com.blaineam.haven.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Holds text shared into Haven from another app (e.g. a YouTube or web link via the system share
 * sheet). The composer picks it up and prefills the draft, then clears it.
 */
object ShareInbox {
    var pending by mutableStateOf<String?>(null)
        private set
    // Media refs (already staged into LocalMedia) shared in from another app — the composer attaches
    // them to the next post.
    var pendingMedia by mutableStateOf<List<String>>(emptyList())
        private set

    fun offer(text: String?) {
        if (!text.isNullOrBlank()) pending = text.trim()
    }

    fun offerMedia(refs: List<String>) {
        if (refs.isNotEmpty()) pendingMedia = pendingMedia + refs
    }

    fun take(): String? {
        val t = pending
        pending = null
        return t
    }

    fun takeMedia(): List<String> {
        val m = pendingMedia
        pendingMedia = emptyList()
        return m
    }
}
