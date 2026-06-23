package com.blaineam.haven.core

import android.content.Context

/**
 * Wires the Android Context/JavaVM into the Rust core's `ndk-context` so iroh's TLS stack can
 * reach the system trust store. Must run once before any networking (node/relay) starts —
 * otherwise the node panics with "android context was not initialized".
 */
object NativeBridge {
    @Volatile private var inited = false

    fun ensureAndroidContext(context: Context) {
        if (inited) return
        synchronized(this) {
            if (inited) return
            System.loadLibrary("haven_ffi")           // make the JNI symbol bindable by the JVM
            nativeInitAndroidContext(context.applicationContext)
            inited = true
        }
    }

    private external fun nativeInitAndroidContext(context: Context)
}
