import java.net.URI
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Downloads the official rclone linux-arm64 static binary at build time and places it
// in jniLibs so Android's package installer extracts it to nativeLibraryDir at install
// time. nativeLibraryDir is the only location SELinux allows exec from on Android 10+.
// The linux-arm64 binary is a statically-linked PIE (ET_DYN) Go binary; it runs on
// Android arm64 because Android shares the Linux kernel syscall ABI.
tasks.register("downloadRcloneBinary") {
    val outputFile = layout.projectDirectory
        .file("src/main/jniLibs/arm64-v8a/librclone.so").asFile

    onlyIf("rclone binary not bundled yet") {
        !outputFile.exists() || outputFile.length() == 0L
    }

    doLast {
        println("> Downloading rclone linux-arm64 static binary…")
        outputFile.parentFile.mkdirs()

        val zipUrl = URI("https://downloads.rclone.org/rclone-current-linux-arm64.zip").toURL()

        zipUrl.openStream().use { raw ->
            ZipInputStream(raw).use { zis ->
                var found = false
                var entry = zis.nextEntry
                while (entry != null) {
                    // Match "rclone-vX.XX.X-linux-arm64/rclone" (not rclone.1 man page)
                    if (!entry.isDirectory && entry.name.endsWith("/rclone")) {
                        outputFile.outputStream().use { out -> zis.copyTo(out) }
                        found = true
                        break
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
                if (!found) error("rclone binary not found inside downloaded zip")
            }
        }

        println("> librclone.so ready: ${outputFile.absolutePath} (${outputFile.length() / 1_048_576} MB)")
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.apprclone.app_rclone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
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