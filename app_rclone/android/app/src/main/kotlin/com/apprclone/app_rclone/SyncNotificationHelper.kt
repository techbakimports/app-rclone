package com.apprclone.app_rclone

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat

class SyncNotificationHelper(private val context: Context) {

    private val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun buildProgressNotif(title: String, percent: Int, detail: String): Notification {
        val indeterminate = percent <= 0
        return NotificationCompat.Builder(context, RcloneForegroundService.CHANNEL_ONGOING)
            .setContentTitle(title)
            .setContentText(detail)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setProgress(100, percent.coerceIn(0, 100), indeterminate)
            .build()
    }

    fun updateProgress(id: Int, title: String, percent: Int, detail: String) {
        nm.notify(id, buildProgressNotif(title, percent, detail))
    }

    fun postSuccess(id: Int, title: String, summary: String) {
        nm.cancel(id)
        val notif = NotificationCompat.Builder(context, RcloneForegroundService.CHANNEL_SUCCESS)
            .setContentTitle(title)
            .setContentText(summary)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setAutoCancel(true)
            .build()
        nm.notify(id + 10_000, notif)
    }

    fun postFailure(id: Int, title: String, error: String) {
        nm.cancel(id)
        val notif = NotificationCompat.Builder(context, RcloneForegroundService.CHANNEL_FAILURE)
            .setContentTitle(title)
            .setContentText(error)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setAutoCancel(true)
            .build()
        nm.notify(id + 20_000, notif)
    }
}
