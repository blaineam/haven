package com.blaineam.haven

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import android.net.Uri
import androidx.core.content.IntentCompat
import com.blaineam.haven.core.DemoEnv
import com.blaineam.haven.core.HavenNet
import com.blaineam.haven.core.LocalMedia
import com.blaineam.haven.core.ShareInbox
import com.blaineam.haven.core.isVideoUri
import com.blaineam.haven.core.loadAndDownscale
import com.blaineam.haven.core.readVideoBytes
import com.blaineam.haven.ui.HavenAppTheme
import com.blaineam.haven.ui.RootScreen

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        DemoEnv.configure(intent)   // DEBUG-only: arms demo mode from launch-intent extras
        handleShare(intent)
        setContent {
            HavenAppTheme {
                RootScreen()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    /** Text / links / photos / videos shared into Haven → prefill the composer + attach media. */
    private fun handleShare(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text") == true) {
                    ShareInbox.offer(intent.getStringExtra(Intent.EXTRA_TEXT))
                } else {
                    IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                        ?.let { ingestSharedMedia(listOf(it)) }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                    ?.let { ingestSharedMedia(it) }
            }
        }
    }

    /** Stage shared content-URIs into LocalMedia (we hold temporary read grants for the intent's
     *  life, so copy the bytes now) and hand the refs to the composer. */
    private fun ingestSharedMedia(uris: List<Uri>) {
        val cid = HavenNet.activeCircle.value
        val refs = uris.mapNotNull { uri ->
            if (isVideoUri(this, uri)) readVideoBytes(this, uri)?.let { LocalMedia.store(cid, it, isVideo = true) }
            else loadAndDownscale(this, uri)?.let { LocalMedia.store(cid, it) }
        }
        ShareInbox.offerMedia(refs)
    }
}
