package com.apprclone.app_rclone

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.*
import java.util.Base64
import java.util.concurrent.Executors

/**
 * Minimal WebDAV server that exposes an Android SAF document tree to rclone.
 * Rclone connects as webdav://127.0.0.1:<port> with --webdav-vendor=other.
 * No external library needed — implements the HTTP protocol subset that rclone uses.
 */
class SafWebDavBridge(private val context: Context, private val treeUri: Uri) {

    val port: Int
    val user = "safbridge"
    val password: String

    private val server: ServerSocket
    private val pool = Executors.newCachedThreadPool()
    @Volatile private var running = false

    init {
        server = ServerSocket(0)
        port = server.localPort
        val buf = ByteArray(16)
        SecureRandom().nextBytes(buf)
        password = Base64.getUrlEncoder().withoutPadding().encodeToString(buf)
    }

    fun start() {
        running = true
        pool.submit {
            while (running) {
                runCatching { pool.submit { handleSocket(server.accept()) } }
            }
        }
    }

    fun stop() {
        running = false
        server.runCatching { close() }
        pool.shutdown()
    }

    // ── Connection handler ───────────────────────────────────────────────────

    private fun handleSocket(socket: Socket) { socket.use {
        runCatching {
            val input = socket.getInputStream()
            val output = socket.getOutputStream()

            val requestLine = readLine(input).trim()
            if (requestLine.isEmpty()) return@runCatching
            val parts = requestLine.split(" ")
            if (parts.size < 2) return@runCatching
            val method = parts[0].uppercase()
            val rawPath = parts[1].split("?")[0]
            val path = urlDecode(rawPath)

            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = readLine(input)
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                if (colon > 0) {
                    headers[line.substring(0, colon).trim().lowercase()] =
                        line.substring(colon + 1).trim()
                }
            }

            if (!checkAuth(headers["authorization"])) {
                write(output, 401, "Unauthorized",
                    mapOf("WWW-Authenticate" to "Basic realm=\"safbridge\""))
                return@runCatching
            }

            when (method) {
                "OPTIONS"  -> handleOptions(output)
                "PROPFIND" -> handlePropfind(path, headers["depth"] ?: "1", output)
                "GET"      -> handleGet(path, headOnly = false, output)
                "HEAD"     -> handleGet(path, headOnly = true, output)
                "PUT"      -> handlePut(path, input, headers["content-length"]?.toLongOrNull() ?: 0L, output)
                "DELETE"   -> handleDelete(path, output)
                "MKCOL"    -> handleMkcol(path, output)
                "MOVE"     -> handleMove(path, headers["destination"] ?: "", output)
                else       -> write(output, 405, "Method Not Allowed")
            }
        }
    } }

    // ── WebDAV handlers ──────────────────────────────────────────────────────

    private fun handleOptions(out: OutputStream) {
        write(out, 200, "OK", mapOf(
            "Allow" to "OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, PROPFIND",
            "DAV"   to "1",
        ))
    }

    private fun handlePropfind(path: String, depth: String, out: OutputStream) {
        val doc = resolveDoc(path) ?: return write(out, 404, "Not Found")
        val sdf = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("GMT")
        }
        val xml = buildString {
            append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
            append("<D:multistatus xmlns:D=\"DAV:\">\n")
            appendEntry(path.ifEmpty { "/" }, doc, sdf)
            if (depth != "0" && doc.isDirectory) {
                doc.listFiles().forEach { child ->
                    appendEntry("${path.trimEnd('/')}/${child.name}", child, sdf)
                }
            }
            append("</D:multistatus>")
        }
        val body = xml.toByteArray(Charsets.UTF_8)
        write(out, 207, "Multi-Status", mapOf(
            "Content-Type"   to "application/xml; charset=UTF-8",
            "Content-Length" to body.size.toString(),
        ), body)
    }

    private fun StringBuilder.appendEntry(href: String, doc: DocumentFile, sdf: SimpleDateFormat) {
        val h = href.replace("&", "&amp;").replace(" ", "%20")
        val name = (doc.name ?: "").replace("&", "&amp;").replace("<", "&lt;")
        append("  <D:response><D:href>$h</D:href><D:propstat><D:prop>")
        append("<D:displayname>$name</D:displayname>")
        if (!doc.isDirectory) append("<D:getcontentlength>${doc.length()}</D:getcontentlength>")
        append("<D:getlastmodified>${sdf.format(Date(doc.lastModified()))}</D:getlastmodified>")
        append("<D:resourcetype>${if (doc.isDirectory) "<D:collection/>" else ""}</D:resourcetype>")
        append("</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>\n")
    }

    private fun handleGet(path: String, headOnly: Boolean, out: OutputStream) {
        val doc = resolveDoc(path) ?: return write(out, 404, "Not Found")
        if (doc.isDirectory) return write(out, 405, "Method Not Allowed")
        val headers = mapOf(
            "Content-Type"   to "application/octet-stream",
            "Content-Length" to doc.length().toString(),
        )
        if (headOnly) {
            write(out, 200, "OK", headers)
        } else {
            writeHeader(out, 200, "OK", headers)
            context.contentResolver.openInputStream(doc.uri)?.use { it.copyTo(out) }
            out.flush()
        }
    }

    private fun handlePut(path: String, body: InputStream, contentLength: Long, out: OutputStream) {
        val (parentPath, fileName) = splitPath(path) ?: return write(out, 409, "Conflict")
        val parent = resolveDoc(parentPath) ?: return write(out, 409, "Conflict")
        val isNew = parent.findFile(fileName) == null
        val target = parent.findFile(fileName)
            ?: parent.createFile("application/octet-stream", fileName)
            ?: return write(out, 500, "Internal Server Error")
        context.contentResolver.openOutputStream(target.uri, "wt")?.use { dst ->
            if (contentLength > 0) copyBytes(body, dst, contentLength) else body.copyTo(dst)
        } ?: return write(out, 500, "Internal Server Error")
        write(out, if (isNew) 201 else 204, if (isNew) "Created" else "No Content")
    }

    private fun handleDelete(path: String, out: OutputStream) {
        val doc = resolveDoc(path) ?: return write(out, 404, "Not Found")
        if (doc.delete()) write(out, 204, "No Content") else write(out, 500, "Internal Server Error")
    }

    private fun handleMkcol(path: String, out: OutputStream) {
        val (parentPath, dirName) = splitPath(path) ?: return write(out, 409, "Conflict")
        val parent = resolveDoc(parentPath) ?: return write(out, 409, "Conflict")
        if (parent.findFile(dirName) != null) return write(out, 405, "Method Not Allowed")
        if (parent.createDirectory(dirName) != null) write(out, 201, "Created")
        else write(out, 500, "Internal Server Error")
    }

    private fun handleMove(path: String, destHeader: String, out: OutputStream) {
        if (destHeader.isEmpty()) return write(out, 400, "Bad Request")
        val destPath = runCatching { Uri.parse(destHeader).path ?: "" }.getOrDefault("")
        if (destPath.isEmpty()) return write(out, 400, "Bad Request")

        val src = resolveDoc(path) ?: return write(out, 404, "Not Found")
        val (destParentPath, destName) = splitPath(destPath) ?: return write(out, 409, "Conflict")
        val destParent = resolveDoc(destParentPath) ?: return write(out, 409, "Conflict")

        runCatching {
            destParent.findFile(destName)?.delete()
            val srcParentUri = src.parentFile?.uri ?: treeUri
            val newUri = DocumentsContract.moveDocument(
                context.contentResolver, src.uri, srcParentUri, destParent.uri
            ) ?: error("moveDocument returned null")
            if (destName != src.name) {
                DocumentFile.fromSingleUri(context, newUri)?.renameTo(destName)
            }
            write(out, 201, "Created")
        }.onFailure { write(out, 500, "Internal Server Error") }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun resolveDoc(path: String): DocumentFile? {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return null
        val parts = path.trimStart('/').split('/').filter { it.isNotEmpty() }
        return parts.fold(root as DocumentFile?) { doc, seg -> doc?.findFile(seg) }
    }

    private fun splitPath(path: String): Pair<String, String>? {
        val parts = path.trimStart('/').split('/').filter { it.isNotEmpty() }
        if (parts.isEmpty()) return null
        val parent = "/" + parts.dropLast(1).joinToString("/")
        return parent to parts.last()
    }

    private fun checkAuth(header: String?): Boolean {
        val expected = "Basic " + Base64.getEncoder()
            .encodeToString("$user:$password".toByteArray())
        return header == expected
    }

    private fun readLine(stream: InputStream): String {
        val sb = StringBuilder()
        var cr = false
        while (true) {
            val b = stream.read()
            if (b == -1) break
            if (b == '\r'.code) { cr = true; continue }
            if (b == '\n'.code) break
            if (cr) { sb.append('\r'); cr = false }
            sb.append(b.toChar())
        }
        return sb.toString()
    }

    private fun copyBytes(src: InputStream, dst: OutputStream, count: Long) {
        val buf = ByteArray(8192)
        var rem = count
        while (rem > 0) {
            val n = src.read(buf, 0, minOf(buf.size.toLong(), rem).toInt())
            if (n == -1) break
            dst.write(buf, 0, n)
            rem -= n
        }
    }

    private fun urlDecode(s: String): String =
        runCatching { java.net.URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)

    private fun writeHeader(out: OutputStream, code: Int, status: String, extra: Map<String, String> = emptyMap()) {
        val sb = StringBuilder("HTTP/1.1 $code $status\r\n")
        extra.forEach { (k, v) -> sb.append("$k: $v\r\n") }
        sb.append("Connection: close\r\n\r\n")
        out.write(sb.toString().toByteArray(Charsets.UTF_8))
    }

    private fun write(out: OutputStream, code: Int, status: String,
                      extra: Map<String, String> = emptyMap(), body: ByteArray = byteArrayOf()) {
        val headers = extra.toMutableMap()
        if (!headers.containsKey("Content-Length")) headers["Content-Length"] = body.size.toString()
        writeHeader(out, code, status, headers)
        if (body.isNotEmpty()) out.write(body)
        out.flush()
    }
}
