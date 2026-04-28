package com.apprclone.app_rclone

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.apprclone.app_rclone/rclone"
    private val authChannelName = "com.apprclone.app_rclone/auth"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var authEventSink: EventChannel.EventSink? = null
    private var authProcess: Process? = null

    // URL regex for auth flow
    private val urlRegex = Regex("""https?://\S+""")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, authChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
                    authEventSink = eventSink
                }
                override fun onCancel(arguments: Any?) {
                    authEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractBinary" -> {
                        val path = findOrExtractBinary()
                        if (path != null) result.success(path)
                        else result.error("BINARY_NOT_FOUND", "rclone binary not available", null)
                    }
                    "getConfigPath" -> result.success(configPath())
                    "startDaemon" -> {
                        val binaryPath = call.argument<String>("binaryPath") ?: run {
                            result.error("MISSING_ARG", "binaryPath required", null)
                            return@setMethodCallHandler
                        }
                        val cfgPath = call.argument<String>("configPath") ?: run {
                            result.error("MISSING_ARG", "configPath required", null)
                            return@setMethodCallHandler
                        }
                        startDaemon(binaryPath, cfgPath)
                        result.success(null)
                    }
                    "stopDaemon" -> {
                        stopDaemon()
                        result.success(null)
                    }
                    "isDaemonRunning" -> result.success(RcloneForegroundService.isRunning)
                    "getLogs" -> result.success(RcloneForegroundService.getLogsSnapshot())
                    "clearLogs" -> {
                        RcloneForegroundService.clearLogs()
                        result.success(null)
                    }
                    "startAuth" -> {
                        val type = call.argument<String>("type") ?: run {
                            result.error("MISSING_ARG", "type required", null)
                            return@setMethodCallHandler
                        }
                        val binaryPath = findOrExtractBinary() ?: run {
                            result.error("BINARY_NOT_FOUND", "Binary not available", null)
                            return@setMethodCallHandler
                        }
                        // Return immediately; events arrive on the auth EventChannel
                        result.success(null)
                        launchAuthProcess(binaryPath, configPath(), type)
                    }
                    "cancelAuth" -> {
                        authProcess?.destroyForcibly()
                        authProcess = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Binary ────────────────────────────────────────────────────────────────

    private fun findOrExtractBinary(): String? {
        val dest = File(filesDir, "rclone")
        if (dest.exists() && dest.length() > 0) {
            dest.setExecutable(true, false)
            return dest.absolutePath
        }
        return try {
            assets.open("flutter_assets/assets/rclone/rclone").use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            }
            dest.setExecutable(true, false)
            dest.absolutePath
        } catch (_: Exception) {
            null  // asset not bundled; caller must trigger download
        }
    }

    private fun configPath(): String = File(filesDir, "rclone.conf").absolutePath

    // ── Daemon ────────────────────────────────────────────────────────────────

    private fun startDaemon(binaryPath: String, configPath: String) {
        val intent = Intent(this, RcloneForegroundService::class.java).apply {
            action = RcloneForegroundService.ACTION_START
            putExtra(RcloneForegroundService.EXTRA_BINARY_PATH, binaryPath)
            putExtra(RcloneForegroundService.EXTRA_CONFIG_PATH, configPath)
        }
        startForegroundService(intent)
    }

    private fun stopDaemon() {
        val intent = Intent(this, RcloneForegroundService::class.java).apply {
            action = RcloneForegroundService.ACTION_STOP
        }
        startService(intent)
    }

    // ── OAuth auth flow ───────────────────────────────────────────────────────

    private fun launchAuthProcess(binaryPath: String, configPath: String, type: String) {
        authProcess?.destroyForcibly()
        Thread {
            try {
                val pb = ProcessBuilder(
                    binaryPath, "authorize", type,
                    "--auth-no-open-browser",
                    "--config=$configPath",
                )
                pb.redirectErrorStream(true)
                val process = pb.start()
                authProcess = process

                val reader = process.inputStream.bufferedReader()
                var urlEmitted = false
                val tokenBuf = StringBuilder()
                var inTokenBlock = false

                for (line in reader.lineSequence()) {
                    // Emit auth URL as soon as we see it
                    if (!urlEmitted) {
                        val match = urlRegex.find(line)
                        if (match != null) {
                            urlEmitted = true
                            val url = match.value
                            mainHandler.post {
                                authEventSink?.success(mapOf("type" to "url", "url" to url))
                            }
                        }
                    }
                    // Detect token block boundaries
                    if (line.contains("Paste the following into your remote machine")) {
                        inTokenBlock = true
                        continue
                    }
                    if (inTokenBlock && line.contains("<---End paste")) {
                        val token = tokenBuf.toString().trim()
                        mainHandler.post {
                            authEventSink?.success(mapOf("type" to "token", "token" to token))
                        }
                        break
                    }
                    if (inTokenBlock) {
                        tokenBuf.append(line)
                    }
                }
                process.waitFor()
            } catch (e: Exception) {
                mainHandler.post {
                    authEventSink?.error("AUTH_FAILED", e.message, null)
                }
            } finally {
                authProcess = null
            }
        }.start()
    }
}
