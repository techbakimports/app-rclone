import java.net.URL
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Downloads the rclone linux-arm64 static binary at build time and places it
// in assets so the app works offline from the first launch.
tasks.register("downloadRcloneBinary") {
    val outputFile = layout.projectDirectory.file("../../assets/rclone/rclone").asFile

    // Skip if the binary is already present (avoids re-downloading every build).
    onlyIf("rclone binary not bundled yet") {
        !outputFile.exists() || outputFile.length() == 0L
    }

    doLast {
        println("> Downloading rclone linux-arm64 binary…")
        outputFile.parentFile.mkdirs()

        val zipUrl = URL("https://downloads.rclone.org/rclone-current-linux-arm64.zip")
        zipUrl.openStream().use { raw ->
            ZipInputStream(raw).use { zis ->
                var found = false
                var entry = zis.nextEntry
                while (entry != null) {
                    // Match "rclone-vX.XX.X-linux-arm64/rclone" (not rclone.1 man page)
                    if (!entry.isDirectory && entry.name.endsWith("/rclone")) {
                        outputFile.outputStream().use { out -> zis.copyTo(out) }
                        found = true
                        println("> rclone binary saved: ${outputFile.absolutePath} (${outputFile.length()} bytes)")
                        break
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
                if (!found) error("rclone binary not found inside downloaded zip")
            }
        }
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
