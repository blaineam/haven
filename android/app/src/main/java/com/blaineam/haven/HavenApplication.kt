package com.blaineam.haven

import android.app.Application
import com.blaineam.haven.core.Notifications
import com.blaineam.haven.core.SyncWorker

/** App entry. FFI/identity init is lazy via HavenCore.get(); here we wire background sync. */
class HavenApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannel(this)
        SyncWorker.schedule(this)
    }
}
