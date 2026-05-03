package com.apprclone.app_rclone

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.result.contract.ActivityResultContracts
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

    private val urlRegex = Regex("""https?://\S+""")

    private val OPEN_DOC_TREE_REQ_CODE = 1001

    // SAF document-tree picker
    private var safPickCallback: MethodChannel.Result? = null

    // Active SAF WebDAV bridge (at most one at a time)
    private var safBridge: SafWebDavBridge? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OPEN_DOC_TREE_REQ_CODE) {
            val cb = safPickCallback ?: return
            safPickCallback = null
            if (resultCode != android.app.Activity.RESULT_OK || data == null) {
                cb.success(null)
                return
            }
            val uri = data.data
            if (uri == null) {
                cb.success(null)
                return
            }
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            cb.success(uri.toString())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, authChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { authEventSink = sink }
                override fun onCancel(args: Any?) { authEventSink = null }
            })

        // Run the MethodChannel on a background thread so heavy operations
        // (log serialization, file I/O) never block the Android main thread.
        // openDocumentTree is the only handler that needs the main thread
        // (startActivityForResult requirement) — it posts back via mainHandler.
        val bgQueue = flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            bgQueue,
        ).setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Binary ────────────────────────────────────────────────
                    "extractBinary" -> {
                        val path = findOrExtractBinary()
                        if (path != null) result.success(path)
                        else result.error("BINARY_NOT_FOUND", "rclone binary not available", null)
                    }
                    "getConfigPath" -> result.success(configPath())
                    "setExecutable" -> {
                        val path = call.argument<String>("path") ?: run {
                            result.error("MISSING_ARG", "path required", null); return@setMethodCallHandler
                        }
                        File(path).setExecutable(true, false)
                        result.success(null)
                    }

                    // ── Daemon ────────────────────────────────────────────────
                    "startDaemon" -> {
                        val bp = call.argument<String>("binaryPath") ?: run {
                            result.error("MISSING_ARG", "binaryPath required", null); return@setMethodCallHandler
                        }
                        val cp = call.argument<String>("configPath") ?: run {
                            result.error("MISSING_ARG", "configPath required", null); return@setMethodCallHandler
                        }
                        startDaemon(bp, cp)
                        result.success(null)
                    }
                    "stopDaemon" -> { stopDaemon(); result.success(null) }
                    "isDaemonRunning" -> result.success(RcloneForegroundService.isRunning)
                    "getDaemonCredentials" -> result.success(
                        mapOf(
                            "port" to RcloneForegroundService.daemonPort,
                            "user" to RcloneForegroundService.daemonUser,
                            "pass" to RcloneForegroundService.daemonPass,
                        )
                    )

                    // ── Logs ──────────────────────────────────────────────────
                    "getLogs" -> result.success(RcloneForegroundService.getLogsSnapshot())
                    "clearLogs" -> { RcloneForegroundService.clearLogs(); result.success(null) }

                    // ── OAuth auth flow ───────────────────────────────────────
                    "startAuth" -> {
                        val type = call.argument<String>("type") ?: run {
                            result.error("MISSING_ARG", "type required", null); return@setMethodCallHandler
                        }
                        val bp = findOrExtractBinary() ?: run {
                            result.error("BINARY_NOT_FOUND", "binary not available", null); return@setMethodCallHandler
                        }
                        result.success(null)
                        launchAuthProcess(bp, configPath(), type)
                    }
                    "cancelAuth" -> { authProcess?.destroyForcibly(); authProcess = null; result.success(null) }

                    // ── SAF ───────────────────────────────────────────────────
                    "openDocumentTree" -> {
                        if (safPickCallback != null) {
                            result.error("BUSY", "A picker is already open", null)
                            return@setMethodCallHandler
                        }
                        safPickCallback = result
                        // startActivityForResult must run on the main thread
                        mainHandler.post {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            startActivityForResult(intent, OPEN_DOC_TREE_REQ_CODE)
                        }
                    }
                    "startSafBridge" -> {
                        val treeUri = call.argument<String>("treeUri") ?: run {
                            result.error("MISSING_ARG", "treeUri required", null); return@setMethodCallHandler
                        }
                        safBridge?.stop()
                        val bridge = SafWebDavBridge(this, Uri.parse(treeUri))
                        bridge.start()
                        safBridge = bridge
                        result.success(mapOf(
                            "port" to bridge.port,
                            "user" to bridge.user,
                            "pass" to bridge.password,
                        ))
                    }
                    "stopSafBridge" -> {
                        safBridge?.stop()
                        safBridge = null
                        result.success(null)
                    }

                    // ── Background sync jobs (WorkManager) ────────────────────
                    "enqueueSyncJob" -> {
                        val op  = call.argument<String>("operation") ?: run {
                            result.error("MISSING_ARG", "operation required", null); return@setMethodCallHandler
                        }
                        val src = call.argument<String>("srcFs") ?: run {
                            result.error("MISSING_ARG", "srcFs required", null); return@setMethodCallHandler
                        }
                        val dst = call.argument<String>("dstFs") ?: run {
                            result.error("MISSING_ARG", "dstFs required", null); return@setMethodCallHandler
                        }
                        val label = call.argument<String>("label") ?: "$op $src"
                        val jobId = SyncWorker.enqueue(this, op, src, dst, label)
                        result.success(jobId)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Binary helpers ────────────────────────────────────────────────────────

    private fun findOrExtractBinary(): String? {
        // Primary: binary extracted by Android from jniLibs at install time.
        // nativeLibraryDir is the only location Android 10+ SELinux allows exec from.
        val nativeLib = File(applicationInfo.nativeLibraryDir, "librclone.so")
        if (nativeLib.exists() && nativeLib.length() > 0) {
            return nativeLib.absolutePath
        }
        // Fallback: copy from assets (works on Android < 10; blocked by SELinux on 10+).
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
            null
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
        startService(Intent(this, RcloneForegroundService::class.java).apply {
            action = RcloneForegroundService.ACTION_STOP
        })
    }

    // ── OAuth ─────────────────────────────────────────────────────────────────

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
                    if (!urlEmitted) {
                        urlRegex.find(line)?.let { match ->
                            urlEmitted = true
                            mainHandler.post {
                                authEventSink?.success(mapOf("type" to "url", "url" to match.value))
                            }
                        }
                    }
                    if (line.contains("Paste the following into your remote machine")) {
                        inTokenBlock = true; continue
                    }
                    if (inTokenBlock && line.contains("<---End paste")) {
                        val token = tokenBuf.toString().trim()
                        mainHandler.post {
                            authEventSink?.success(mapOf("type" to "token", "token" to token))
                        }
                        break
                    }
                    if (inTokenBlock) tokenBuf.append(line)
                }
                process.waitFor()
            } catch (e: Exception) {
                mainHandler.post { authEventSink?.error("AUTH_FAILED", e.message, null) }
            } finally {
                authProcess = null
            }
        }.start()
    }
}
