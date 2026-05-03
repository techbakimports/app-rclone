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
import org.json.JSONObject
import java.net.ServerSocket
import java.security.SecureRandom
import java.util.Base64

class RcloneForegroundService : Service() {

    companion object {
        const val CHANNEL_ONGOING = "rclone_daemon"
        const val CHANNEL_SUCCESS = "rclone_transfer_ok"
        const val CHANNEL_FAILURE = "rclone_transfer_fail"
        const val NOTIF_DAEMON_ID = 1001

        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_BINARY_PATH = "BINARY_PATH"
        const val EXTRA_CONFIG_PATH = "CONFIG_PATH"

        private const val MAX_LOGS = 1000

        @Volatile var rcloneProcess: Process? = null
        @Volatile var isRunning = false

        // Populated synchronously in onStartCommand before the daemon thread launches,
        // so getDaemonCredentials() can return them immediately.
        @Volatile var daemonPort: Int = 0
        @Volatile var daemonUser: String = "rcloneapp"
        @Volatile var daemonPass: String = ""

        // Latest parsed transfer stats from rclone JSON stderr.
        @Volatile var latestStats: Map<String, Any> = emptyMap()

        private val _logLines = ArrayDeque<String>()

        fun appendLog(line: String) {
            synchronized(_logLines) {
                if (_logLines.size >= MAX_LOGS) _logLines.removeFirst()
                _logLines.addLast(line)
            }
        }

        fun clearLogs() = synchronized(_logLines) { _logLines.clear() }

        fun getLogsSnapshot(): List<String> = synchronized(_logLines) { _logLines.toList() }

        fun allocateCredentials() {
            daemonPort = findFreePort()
            daemonPass = generatePassword()
        }

        private fun findFreePort(): Int = ServerSocket(0).use { it.localPort }

        private fun generatePassword(): String {
            val buf = ByteArray(24)
            SecureRandom().nextBytes(buf)
            return Base64.getUrlEncoder().withoutPadding().encodeToString(buf)
        }
    }

    private lateinit var notificationManager: NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val binaryPath = intent.getStringExtra(EXTRA_BINARY_PATH) ?: return START_NOT_STICKY
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH) ?: return START_NOT_STICKY

                // If already running, just refresh the notification — don't
                // reallocate credentials (that would break getDaemonCredentials).
                if (isRunning) {
                    startForeground(NOTIF_DAEMON_ID, buildOngoingNotification("Running on :$daemonPort"))
                    return START_STICKY
                }

                // Credentials allocated here (main thread) so they're readable
                // by getDaemonCredentials before the background thread starts.
                allocateCredentials()

                startForeground(NOTIF_DAEMON_ID, buildOngoingNotification("Starting…"))
                launchDaemonThread(binaryPath, configPath)
            }
            ACTION_STOP -> {
                stopRclone()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun launchDaemonThread(binaryPath: String, configPath: String) {
        Thread {
            try {
                val binFile = java.io.File(binaryPath)
                appendLog("[INFO] Starting rclone daemon")
                appendLog("[INFO] Binary: $binaryPath (exists=${binFile.exists()}, size=${binFile.length()}, exec=${binFile.canExecute()})")
                appendLog("[INFO] Port: $daemonPort | Config: $configPath")

                val pb = ProcessBuilder(
                    binaryPath,
                    "rcd",
                    "--rc-addr=127.0.0.1:$daemonPort",
                    "--rc-user=$daemonUser",
                    "--rc-pass=$daemonPass",
                    "--config=$configPath",
                    "--log-level=INFO",
                    "--use-json-log",
                )
                pb.redirectErrorStream(true)
                val process = pb.start()
                rcloneProcess = process
                isRunning = true
                updateDaemonNotification("Running on :$daemonPort")

                process.inputStream.bufferedReader().forEachLine { line ->
                    appendLog(formatLogLine(line))
                    extractStats(line)
                }

                val exitCode = process.waitFor()
                appendLog("[WARN] Daemon exited with code $exitCode")
            } catch (e: Exception) {
                appendLog("[ERROR] Failed to start daemon: ${e.javaClass.simpleName}: ${e.message}")
            } finally {
                isRunning = false
                daemonPort = 0
            }
        }.start()
    }

    // Extracts the human-readable message from a JSON log line, falling back to raw.
    private fun formatLogLine(raw: String): String {
        return try {
            val obj = JSONObject(raw)
            val level = obj.optString("level", "info").uppercase()
            val msg = obj.optString("msg", raw)
            "[$level] $msg"
        } catch (_: Exception) {
            raw
        }
    }

    // Parses rclone transfer stats from JSON stderr into latestStats.
    private fun extractStats(raw: String) {
        try {
            val obj = JSONObject(raw)
            if (!obj.has("stats")) return
            val stats = obj.getJSONObject("stats")
            val map = mutableMapOf<String, Any>()
            stats.keys().forEach { key -> map[key] = stats.get(key) }
            latestStats = map
        } catch (_: Exception) {}
    }

    private fun stopRclone() {
        rcloneProcess?.destroy()
        rcloneProcess = null
        isRunning = false
        daemonPort = 0
    }

    override fun onDestroy() {
        stopRclone()
        super.onDestroy()
    }

    private fun updateDaemonNotification(text: String) {
        notificationManager.notify(NOTIF_DAEMON_ID, buildOngoingNotification(text))
    }

    private fun createNotificationChannels() {
        val channels = listOf(
            NotificationChannel(CHANNEL_ONGOING, "Rclone Daemon", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while the rclone daemon is active"
                setShowBadge(false)
            },
            NotificationChannel(CHANNEL_SUCCESS, "Transfer Complete", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Shown when a transfer finishes successfully"
            },
            NotificationChannel(CHANNEL_FAILURE, "Transfer Failed", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Shown when a transfer fails or is cancelled"
            },
        )
        notificationManager.createNotificationChannels(channels)
    }

    private fun buildOngoingNotification(status: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ONGOING)
            .setContentTitle("RcloneApp")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }
}
