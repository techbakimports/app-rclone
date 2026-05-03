import org.tukaani.xz.XZInputStream
import java.net.URI
import java.util.zip.GZIPInputStream

// XZ decompression for data.tar.xz inside the Termux .deb package.
// ar/tar parsing is done manually -- no commons-compress (avoids Gradle classpath conflict).
buildscript {
    repositories { mavenCentral() }
    dependencies {
        classpath("org.tukaani:xz:1.10")
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Downloads the rclone binary for Android arm64 from the Termux apt repository.
// Termux compiles rclone with GOOS=android GOARCH=arm64 (Android NDK), so the
// binary uses /system/bin/linker64 and works on any Android 8+ device without Termux.
// The binary is placed in jniLibs so Android's package installer extracts it to
// nativeLibraryDir at install time -- the only location SELinux allows exec from on Android 10+.
tasks.register("downloadRcloneBinary") {
    val outputFile = layout.projectDirectory
        .file("src/main/jniLibs/arm64-v8a/librclone.so").asFile

    onlyIf("rclone Android binary not bundled yet") {
        !outputFile.exists() || outputFile.length() == 0L
    }

    doLast {
        outputFile.parentFile.mkdirs()

        // Read exactly `count` bytes; throws on premature EOF.
        fun java.io.InputStream.readExact(count: Int): ByteArray {
            val buf = ByteArray(count)
            var pos = 0
            while (pos < count) {
                val n = read(buf, pos, count - pos)
                check(n >= 0) { "Unexpected EOF at byte $pos/$count" }
                pos += n
            }
            return buf
        }

        // Skip exactly `count` bytes, working around skip() returning 0.
        fun java.io.InputStream.skipExact(count: Long) {
            var rem = count
            while (rem > 0) {
                val s = skip(rem)
                if (s > 0) rem -= s else { read(); rem-- }
            }
        }

        // Extract a null-terminated string from a POSIX tar header field.
        // tar stores filenames as: content bytes + first NUL + NUL padding to field length.
        fun ByteArray.tarName(off: Int, len: Int): String {
            var end = 0
            while (end < len && this[off + end] != 0.toByte()) end++
            return String(this, off, end, Charsets.ISO_8859_1)
        }

        // Parse an octal size field from a POSIX tar header (null or space terminated).
        fun ByteArray.tarOctal(off: Int, len: Int): Long {
            val s = String(this, off, len, Charsets.ISO_8859_1).trim()
            var i = 0
            while (i < s.length && s[i] == '0') i++   // skip leading zeros
            var result = 0L
            while (i < s.length && s[i] in '0'..'7') {
                result = result * 8 + (s[i] - '0')
                i++
            }
            return result
        }

        // ---- Step 1: Fetch Termux Packages.gz index, find rclone .deb path ----------
        println("> Fetching Termux package index for aarch64...")
        val indexUrl = URI(
            "https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz"
        ).toURL()

        val debPath = indexUrl.openStream().use { raw ->
            GZIPInputStream(raw).bufferedReader(Charsets.UTF_8).use { reader ->
                var inRclone = false
                var filename: String? = null
                for (line in reader.lineSequence()) {
                    when {
                        line == "Package: rclone" -> inRclone = true
                        inRclone && line.startsWith("Filename: ") -> {
                            filename = line.removePrefix("Filename: ").trim()
                        }
                        inRclone && line.isBlank() -> {
                            if (filename != null) break
                            inRclone = false
                        }
                    }
                }
                filename ?: error("rclone not found in Termux package index")
            }
        }
        println("> Found: $debPath")

        // ---- Step 2: Download .deb, parse ar -> data.tar.xz -> extract rclone ------
        //
        // ar entry header (60 bytes):
        //   [ 0..15]  filename identifier (space-padded ASCII)
        //   [16..27]  modification time   (decimal, space-padded)
        //   [28..33]  owner numeric ID    (decimal, space-padded)
        //   [34..39]  group numeric ID    (decimal, space-padded)
        //   [40..47]  file mode           (octal, space-padded)
        //   [48..57]  file size in bytes  (decimal, space-padded)
        //   [58..59]  end-of-header marker
        //
        // POSIX ustar tar block (512 bytes):
        //   [  0.. 99]  filename     (null-terminated, null-padded)
        //   [124..135]  size in bytes (octal ASCII, null/space-padded)
        val debUrl = URI("https://packages.termux.dev/apt/termux-main/$debPath").toURL()
        println("> Downloading .deb...")

        debUrl.openStream().use { debStream ->
            val magic = debStream.readExact(8)
            check(String(magic, Charsets.US_ASCII) == "!<arch>\n") {
                "Not a valid .deb file (bad ar magic)"
            }

            var binaryFound = false

            while (!binaryFound) {
                val arHeader = try { debStream.readExact(60) } catch (_: Exception) { break }
                // GNU ar sometimes appends '/' to entry names in the identifier field.
                val arName = String(arHeader, 0, 16, Charsets.US_ASCII).trim().trimEnd('/')
                val arSize = String(arHeader, 48, 10, Charsets.US_ASCII).trim().toLongOrNull() ?: break

                println("> ar: '$arName' ($arSize bytes)")

                if (arName.startsWith("data.tar")) {
                    // Read the whole compressed entry into memory before decompressing.
                    // XZInputStream needs a ByteArrayInputStream; feeding it the network
                    // stream directly would fail when the ar entry boundary is reached.
                    val compressed = debStream.readExact(arSize.toInt())
                    println("> Decompressing $arName...")

                    val tarStream: java.io.InputStream = when {
                        arName.endsWith(".xz") -> XZInputStream(compressed.inputStream())
                        arName.endsWith(".gz") -> GZIPInputStream(compressed.inputStream())
                        else -> compressed.inputStream()
                    }

                    tarStream.use { tar ->
                        val hdr = ByteArray(512)
                        while (!binaryFound) {
                            // Read a 512-byte tar block; exit on EOF or end-of-archive.
                            var pos = 0
                            while (pos < 512) {
                                val n = tar.read(hdr, pos, 512 - pos)
                                if (n < 0) { pos = -1; break }
                                pos += n
                            }
                            if (pos < 0 || hdr.all { it == 0.toByte() }) break

                            val name = hdr.tarName(0, 100)
                            val size = hdr.tarOctal(124, 12)
                            val paddedSize = ((size + 511) / 512) * 512

                            if (name.contains("rclone")) {
                                println("> tar: '$name' size=$size")
                            }

                            if (name.endsWith("bin/rclone") && size > 0L) {
                                outputFile.outputStream().use { out ->
                                    var rem = size
                                    val buf = ByteArray(65536)
                                    while (rem > 0) {
                                        val n = tar.read(buf, 0, minOf(buf.size.toLong(), rem).toInt())
                                        if (n < 0) break
                                        out.write(buf, 0, n)
                                        rem -= n
                                    }
                                }
                                // Drain padding bytes to keep stream position consistent.
                                val pad = (paddedSize - size).toInt()
                                if (pad > 0) tar.skipExact(pad.toLong())
                                println("> Extracted: $name (${size / 1_048_576} MB)")
                                binaryFound = true
                            } else if (paddedSize > 0) {
                                tar.skipExact(paddedSize)
                            }
                        }
                    }
                    break
                } else {
                    debStream.skipExact(arSize)
                    if (arSize % 2 != 0L) debStream.skipExact(1) // ar pads entries to even size
                }
            }
        }

        check(outputFile.exists() && outputFile.length() > 0L) {
            "Failed to extract rclone binary from $debPath — check Termux repository"
        }
        println("> librclone.so ready: ${outputFile.length() / 1_048_576} MB (GOOS=android, arm64)")
    }
}

afterEvaluate {
    tasks.named("preBuild") {
        dependsOn("downloadRcloneBinary")
    }
}

android {
    namespace = "com.apprclone.app_rclone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.apprclone.app_rclone"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
}
