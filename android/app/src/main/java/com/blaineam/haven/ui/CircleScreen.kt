package com.blaineam.haven.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.blaineam.haven.core.DEFAULT_CIRCLE
import com.blaineam.haven.core.HavenNet
import com.blaineam.haven.core.PendingRequest
import com.blaineam.haven.core.nowMs
import uniffi.haven_ffi.FeedItemFfi

/** The Circle (feed) — real posts from the shared engine, a composer, and pending requests. */
@Composable
fun CircleScreen(onAddFriend: () -> Unit) {
    var draft by remember { mutableStateOf("") }
    val version by HavenNet.feedVersion          // recompose when the feed changes
    val items: List<FeedItemFfi> = remember(version) {
        runCatching { HavenNet.engine.feed(DEFAULT_CIRCLE, nowMs(), null) }.getOrDefault(emptyList())
    }

    HavenBackground {
        Column(Modifier.fillMaxSize()) {
            // Title bar.
            Row(
                Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 16.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BrandText("Circle", fontSize = 26)
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier.size(40.dp).clip(CircleShape).clickable { onAddFriend() },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.PersonAdd, "Add a friend", tint = HavenTheme.pink) }
            }

            if (HavenNet.pending.isNotEmpty()) {
                HavenNet.pending.forEach { PendingCard(it) }
            }

            if (items.isEmpty()) {
                Column(
                    Modifier.fillMaxWidth().weight(1f).padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("Nothing here yet", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        if (HavenNet.contacts.isEmpty())
                            "Add a friend to start sharing.\nEverything you post is end-to-end encrypted to your circle."
                        else "Say something to your circle below.",
                        color = HavenTheme.textSecondary, fontSize = 14.sp, textAlign = TextAlign.Center,
                    )
                }
            } else {
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(items, key = { it.id }) { PostCard(it) }
                }
            }

            // Composer.
            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Share with your circle…") },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(22.dp),
                    maxLines = 4,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = HavenTheme.pink,
                        cursorColor = HavenTheme.pink,
                    ),
                )
                Spacer(Modifier.size(8.dp))
                Box(
                    Modifier.size(48.dp).clip(CircleShape)
                        .background(HavenTheme.brandHorizontal)
                        .clickable(enabled = draft.isNotBlank()) {
                            HavenNet.post(DEFAULT_CIRCLE, draft.trim()); draft = ""
                        },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Send, "Post", tint = Color.White) }
            }
        }
    }
}

@Composable
private fun PendingCard(req: PendingRequest) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
            .havenCard().padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("${req.name} wants to connect", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text("Safety: ${req.verifyHex.take(12)}…", color = HavenTheme.textSecondary, fontSize = 11.sp)
        }
        Text("Accept", color = HavenTheme.pink, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { HavenNet.approve(req) }.padding(8.dp))
        Text("Ignore", color = HavenTheme.textSecondary,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { HavenNet.dismiss(req) }.padding(8.dp))
    }
}

@Composable
fun PostCard(item: FeedItemFfi) {
    Column(Modifier.fillMaxWidth().havenCard().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(34.dp).clip(CircleShape).background(HavenTheme.brand),
                contentAlignment = Alignment.Center,
            ) { Text(if (item.isMe) "•" else item.authorShort.take(1).uppercase(), color = Color.White, fontSize = 14.sp) }
            Spacer(Modifier.size(10.dp))
            Text(
                if (item.isMe) "You" else item.authorShort,
                color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
            )
        }
        if (item.body.isNotBlank()) {
            Spacer(Modifier.height(10.dp))
            Text(item.body, color = Color.White, fontSize = 15.sp)
        }
        if (item.reactions.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                item.reactions.forEach { Text("${it.emoji} ${it.count}", fontSize = 13.sp, color = HavenTheme.textSecondary) }
            }
        }
    }
}
