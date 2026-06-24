package com.blaineam.haven.core

import android.content.Context
import uniffi.haven_ffi.S3ConfigFfi

/**
 * BYO-storage (S3-compatible bucket) config for self-sync, the Android counterpart of iOS's
 * `SharedStore.ownerS3()`. Holds the 5 fields needed to talk to a user-owned bucket
 * (endpoint/region/bucket/accessKey/secretKey) so multi-device self-sync works over an arbitrary
 * bucket with NO relay required, matching iOS/desktop.
 *
 * Plain SharedPreferences (`haven.storage`). These are the user's own credentials for their own
 * bucket; they never leave the device except to authenticate to that bucket.
 */
object StorageStore {

    private const val PREFS = "haven.storage"
    private const val KEY_ENDPOINT = "endpoint"
    private const val KEY_REGION = "region"
    private const val KEY_BUCKET = "bucket"
    private const val KEY_ACCESS = "accessKey"
    private const val KEY_SECRET = "secretKey"

    data class Config(
        val endpoint: String = "",
        val region: String = "",
        val bucket: String = "",
        val accessKey: String = "",
        val secretKey: String = "",
    ) {
        /** Configured only when every field needed to reach a bucket is present. */
        val isConfigured: Boolean
            get() = endpoint.isNotBlank() && region.isNotBlank() && bucket.isNotBlank() &&
                accessKey.isNotBlank() && secretKey.isNotBlank()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            endpoint = p.getString(KEY_ENDPOINT, "") ?: "",
            region = p.getString(KEY_REGION, "") ?: "",
            bucket = p.getString(KEY_BUCKET, "") ?: "",
            accessKey = p.getString(KEY_ACCESS, "") ?: "",
            secretKey = p.getString(KEY_SECRET, "") ?: "",
        )
    }

    fun save(context: Context, config: Config) {
        prefs(context).edit()
            .putString(KEY_ENDPOINT, config.endpoint.trim())
            .putString(KEY_REGION, config.region.trim())
            .putString(KEY_BUCKET, config.bucket.trim())
            .putString(KEY_ACCESS, config.accessKey.trim())
            .putString(KEY_SECRET, config.secretKey.trim())
            .apply()
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }

    fun isConfigured(context: Context): Boolean = load(context).isConfigured

    /** The FFI config for `s3Put`/`s3Get`/`s3List`, or null if not fully configured. */
    fun s3Config(context: Context): S3ConfigFfi? {
        val c = load(context)
        if (!c.isConfigured) return null
        return S3ConfigFfi(
            endpoint = c.endpoint,
            region = c.region,
            bucket = c.bucket,
            accessKey = c.accessKey,
            secretKey = c.secretKey,
        )
    }
}
