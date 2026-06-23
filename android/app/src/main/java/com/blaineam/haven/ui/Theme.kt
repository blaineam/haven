package com.blaineam.haven.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Haven's design system — the single source of brand color, depth, motion and tactile
 * feel, ported from the iOS Theme.swift so the two platforms look like one product.
 */
object HavenTheme {
    val violet = Color(0xFF7C3AED)
    val pink = Color(0xFFEC4899)
    val amber = Color(0xFFF59E0B)

    /** Near-black grouped background, matching the iOS dark grouped background. */
    val background = Color(0xFF0B0B0F)
    val card = Color(0xFF16161D)
    val cardBorder = Color(0x14FFFFFF)
    val textSecondary = Color(0xFF9A9AA8)

    /** The signature sunset gradient (matches the app icon). */
    val brand = Brush.linearGradient(
        colors = listOf(violet, pink, amber),
        start = Offset(0f, 0f),
        end = Offset.Infinite,
    )

    val brandHorizontal = Brush.horizontalGradient(listOf(violet, pink, amber))

    // Motion vocabulary — a small set of springs used everywhere for cohesion.
    fun <T> bouncy() = spring<T>(dampingRatio = 0.68f, stiffness = Spring.StiffnessMediumLow)
    fun <T> smooth() = spring<T>(dampingRatio = 0.85f, stiffness = Spring.StiffnessLow)
    fun <T> snappy() = spring<T>(dampingRatio = 0.70f, stiffness = Spring.StiffnessMedium)
}

private val HavenColorScheme = darkColorScheme(
    primary = HavenTheme.pink,
    secondary = HavenTheme.violet,
    tertiary = HavenTheme.amber,
    background = HavenTheme.background,
    surface = HavenTheme.card,
    onPrimary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun HavenAppTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = HavenColorScheme,
        typography = Typography(),
        content = content,
    )
}

/** Soft branded backdrop: dark base with two gentle brand glows. */
@Composable
fun HavenBackground(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(HavenTheme.background)) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(HavenTheme.pink.copy(alpha = 0.20f), Color.Transparent),
                    center = Offset(900f, -40f),
                    radius = 1200f,
                )
            )
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(HavenTheme.violet.copy(alpha = 0.18f), Color.Transparent),
                    center = Offset(40f, 300f),
                    radius = 1100f,
                )
            )
        )
        content()
    }
}

/** A floating, slightly-bordered card with soft depth. */
fun Modifier.havenCard(): Modifier = this
    .background(HavenTheme.card, RoundedCornerShape(24.dp))

@Composable
fun rememberPressInteraction() = MutableInteractionSource()
