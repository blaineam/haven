package com.blaineam.haven.core

/**
 * Marks a message as "secret" (tap-to-reveal, screenshot-protected). Wire-compatible with iOS
 * (apple/HavenApp/SecretMessages.swift): the flag rides in the body behind a control char (STX,
 * U+0002), so a secret sent from either platform is recognised on the other.
 */
object SecretMessages {
    private const val MARKER = "\u0002"
    fun encode(text: String): String = MARKER + text
    fun isSecret(body: String): Boolean = body.startsWith(MARKER)
    fun text(body: String): String = if (isSecret(body)) body.substring(1) else body
}
