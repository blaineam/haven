package com.blaineam.haven

import android.app.Application

/** App entry. Kept minimal for now; FFI/identity init is lazy via HavenCore.get(). */
class HavenApplication : Application()
