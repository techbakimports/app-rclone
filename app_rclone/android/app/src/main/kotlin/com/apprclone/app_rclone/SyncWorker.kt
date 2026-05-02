package com.apprclone.app_rclone

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.*
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    companion object {
        const val KEY_OPERATION = "operation"
        const val KEY_SRC_FS = "src_fs"
        const val KEY_DST_FS = "dst_fs"
        const val KEY_LABEL = "label"
        const val KEY_NOTIF_ID = "notif_id"

        private val notifCounter = AtomicInteger(2000)

        fun enqueue(
            context: Context,
            operation: String,
            srcFs: String,
            dstFs: String,
            label: String = "$operation $srcFs",
        ): String {
            val notifId = notifCounter.getAndIncrement()
            val request = OneTimeWorkRequestBuilder<SyncWorker>()
                .setInputData(
                    workDataOf(
                        KEY_OPERATION to operation,
                        KEY_SRC_FS to srcFs,
                        KEY_DST_FS to dstFs,
                        KEY_LABEL to label,
                        KEY_NOTIF_ID to notifId,
                    )
                )
                .build()
            WorkManager.getInstance(context).enqueue(request)
            return request.id.toString()
        }
    }

    private val notifHelper = SyncNotificationHelper(applicationContext)
    private val binaryPath = File(applicationContext.filesDir, "rclone").absolutePath
    private val configPath = File(applicationContext.filesDir, "rclone.conf").absolutePath

    @Volatile private var process: Process? = null

    override fun doWork(): Result {
        val operation = inputData.getString(KEY_OPERATION) ?: return Result.failure()
        val srcFs = inputData.getString(KEY_SRC_FS) ?: return Result.failure()
        val dstFs = inputData.getString(KEY_DST_FS) ?: return Result.failure()
        val label = inputData.getString(KEY_LABEL) ?: operation
        val notifId = inputData.getInt(KEY_NOTIF_ID, notifCounter.getAndIncrement())

        if (!File(binaryPath).exists()) return Result.failure(
            workDataOf("error" to "rclone binary not found")
        )

        setForegroundAsync(buildForegroundInfo(notifId, label))

        val args = buildCommand(operation, srcFs, dstFs)
        val pb = ProcessBuilder(args).apply { redirectErrorStream(true) }

        var lastError = ""

        return try {
            val proc = pb.start()
            process = proc

            proc.inputStream.bufferedReader().forEachLine { line ->
                RcloneForegroundService.appendLog(line)
                parseProgressLine(line, notifId, label)
                extractError(line)?.let { lastError = it }
            }

            val exitCode = proc.waitFor()
            if (exitCode == 0) {
                notifHelper.postSuccess(notifId, label, "Transfer complete")
                Result.success()
            } else {
                val msg = lastError.ifBlank { "Exit code $exitCode" }
                notifHelper.postFailure(notifId, label, msg)
                Result.failure(workDataOf("error" to msg))
            }
        } catch (e: Exception) {
            notifHelper.postFailure(notifId, label, e.message ?: "Unknown error")
            Result.failure(workDataOf("error" to (e.message ?: "")))
        }
    }

    override fun onStopped() {
        process?.destroyForcibly()
        super.onStopped()
    }

    override fun getForegroundInfo(): ForegroundInfo {
        val notifId = inputData.getInt(KEY_NOTIF_ID, 2000)
        val label = inputData.getString(KEY_LABEL) ?: "Transfer"
        return buildForegroundInfo(notifId, label)
    }

    private fun buildForegroundInfo(notifId: Int, label: String): ForegroundInfo {
        val notif = notifHelper.buildProgressNotif(label, 0, "Preparing…")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(notifId, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(notifId, notif)
        }
    }

    private fun buildCommand(operation: String, srcFs: String, dstFs: String): List<String> {
        val base = listOf(
            binaryPath,
            operation,
            srcFs,
            dstFs,
            "--config=$configPath",
            "--log-level=INFO",
            "--use-json-log",
            "--stats=2s",
            "--stats-one-line",
        )
        // bisync uses path1/path2 not src/dst, but positional args are the same
        return base
    }

    // Updates the in-progress notification when rclone reports transfer stats.
    private fun parseProgressLine(raw: String, notifId: Int, label: String) {
        try {
            val obj = JSONObject(raw)
            if (!obj.has("stats")) return
            val stats = obj.getJSONObject("stats")
            val totalBytes = stats.optLong("totalBytes", 0)
            val bytes = stats.optLong("bytes", 0)
            val percent = if (totalBytes > 0) ((bytes * 100) / totalBytes).toInt() else 0
            val speed = formatSpeed(stats.optDouble("speed", 0.0))
            notifHelper.updateProgress(notifId, label, percent, "$percent% · $speed")
        } catch (_: Exception) {}
    }

    private fun extractError(raw: String): String? {
        return try {
            val obj = JSONObject(raw)
            if (obj.optString("level") == "error") obj.optString("msg") else null
        } catch (_: Exception) { null }
    }

    private fun formatSpeed(bps: Double): String = when {
        bps >= 1_000_000.0 -> "${"%.1f".format(bps / 1_000_000)} MB/s"
        bps >= 1_000.0 -> "${"%.0f".format(bps / 1_000)} KB/s"
        else -> "${"%.0f".format(bps)} B/s"
    }
}
