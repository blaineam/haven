package com.blaineam.haven.core

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodic background sync (serverless, like the iOS BGAppRefreshTask): poll the circle relay
 * mailbox and post local notifications for anything new. Min interval on Android is 15 minutes.
 */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        runCatching {
            HavenNet.init(applicationContext)
            HavenNet.pollMailbox()
        }
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            Notifications.ensureChannel(context)
            val req = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "haven.sync", ExistingPeriodicWorkPolicy.KEEP, req,
            )
        }
    }
}
