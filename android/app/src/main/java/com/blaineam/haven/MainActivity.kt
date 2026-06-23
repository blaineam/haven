package com.blaineam.haven

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.blaineam.haven.ui.HavenAppTheme
import com.blaineam.haven.ui.RootScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            HavenAppTheme {
                RootScreen()
            }
        }
    }
}
