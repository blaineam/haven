package com.blaineam.haven.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.blaineam.haven.core.AvatarStore
import com.blaineam.haven.core.HavenNet
import com.blaineam.haven.core.ProfileStore

/**
 * A circular avatar that prefers a real photo (from [AvatarStore]), then the person's emoji, then
 * their initial on the brand gradient — the Android counterpart of iOS's `HavenAvatar`.
 *
 * [idOrShort] is a full node-id hex or the short prefix the feed carries (`authorShort`).
 */
@Composable
fun HavenAvatar(idOrShort: String, name: String, size: Dp, isMe: Boolean = false, emojiOverride: String? = null) {
    val v by AvatarStore.version
    val context = LocalContext.current
    val key = if (isMe) HavenNet.nodeIdHex else idOrShort
    val img = remember(key, v) { AvatarStore.image(key) }
    val emoji = when {
        emojiOverride != null -> emojiOverride
        isMe -> ProfileStore.get(context).emoji
        else -> AvatarStore.emoji(idOrShort)
    }
    Box(Modifier.size(size).clip(CircleShape).background(HavenTheme.brand), contentAlignment = Alignment.Center) {
        when {
            img != null -> Image(img, "Avatar", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            emoji.isNotBlank() -> Text(emoji, fontSize = (size.value * 0.5f).sp)
            else -> Text(name.take(1).uppercase().ifBlank { "•" }, color = Color.White,
                fontWeight = FontWeight.Bold, fontSize = (size.value * 0.4f).sp)
        }
    }
}
