package com.apprclone.app_rclone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RcloneForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "rclone_service_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_BINARY_PATH = "BINARY_PATH"
        const val EXTRA_CONFIG_PATH = "CONFIG_PATH"

        private const val MAX_LOGS = 1000

        @Volatile var rcloneProcess: Process? = null
        @Volatile var isRunning = false

        private val _logLines = ArrayDeque<String>()

        fun appendLog(line: String) {
            synchronized(_logLines) {
                if (_logLines.size >= MAX_LOGS) _logLines.removeFirst()
                _logLines.addLast(line)
            }
        }

        fun clearLogs() {
            synchronized(_logLines) { _logLines.clear() }
        }

        fun getLogsSnapshot(): List<String> {
            synchronized(_logLines) { return _logLines.toList() }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val binaryPath = intent.getStringExtra(EXTRA_BINARY_PATH) ?: return START_NOT_STICKY
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH) ?: return START_NOT_STICKY
                startForeground(NOTIFICATION_ID, buildNotification("Daemon running"))
                startRclone(binaryPath, configPath)
            }
            ACTION_STOP -> {
                stopRclone()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun startRclone(binaryPath: String, configPath: String) {
        if (isRunning) return
        Thread {
            try {
                val pb = ProcessBuilder(
                    binaryPath,
                    "rcd",
                    "--rc-no-auth",
                    "--rc-addr=127.0.0.1:5572",
                    "--config=$configPath",
                    "--log-level=INFO",
                )
                pb.redirectErrorStream(true)
                val process = pb.start()
                rcloneProcess = process
                isRunning = true

                process.inputStream.bufferedReader().forEachLine { line ->
                    appendLog(line)
                }
            } catch (e: Exception) {
                appendLog("ERROR: ${e.message}")
            } finally {
                isRunning = false
            }
        }.start()
    }

    private fun stopRclone() {
        rcloneProcess?.destroy()
        rcloneProcess = null
        isRunning = false
    }

    override fun onDestroy() {
        stopRclone()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Rclone Daemon",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Rclone background daemon"
            setShowBadge(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(status: String): Notification {
        val activityIntent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RcloneApp")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }
}
