package com.blaineam.haven.core

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Lightweight observable profile + onboarding state, the Android counterpart of the iOS
 * ProfileStore. Backed by plain SharedPreferences (non-secret display data); the identity
 * itself lives in [HavenCore] / the Keystore.
 */
class ProfileStore private constructor(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("haven.profile", Context.MODE_PRIVATE)

    var onboarded by mutableStateOf(prefs.getBoolean(KEY_ONBOARDED, false))
        private set
    var displayName by mutableStateOf(prefs.getString(KEY_NAME, "") ?: "")
    var bio by mutableStateOf(prefs.getString(KEY_BIO, "") ?: "")
    var emoji by mutableStateOf(prefs.getString(KEY_EMOJI, "🌅") ?: "🌅")

    fun completeOnboarding(name: String, emoji: String) {
        displayName = name
        this.emoji = emoji
        onboarded = true
        prefs.edit()
            .putString(KEY_NAME, name)
            .putString(KEY_EMOJI, emoji)
            .putBoolean(KEY_ONBOARDED, true)
            .apply()
    }

    fun save() {
        prefs.edit()
            .putString(KEY_NAME, displayName)
            .putString(KEY_BIO, bio)
            .putString(KEY_EMOJI, emoji)
            .apply()
    }

    fun reset() {
        onboarded = false
        displayName = ""
        bio = ""
        emoji = "🌅"
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_ONBOARDED = "onboarded"
        private const val KEY_NAME = "name"
        private const val KEY_BIO = "bio"
        private const val KEY_EMOJI = "emoji"

        @Volatile private var instance: ProfileStore? = null
        fun get(context: Context): ProfileStore =
            instance ?: synchronized(this) {
                instance ?: ProfileStore(context).also { instance = it }
            }
    }
}
