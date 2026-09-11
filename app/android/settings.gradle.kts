pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Reads android/app/google-services.json at build time to generate the
    // Firebase config Android resources (call/message push notifications,
    // Phase 3 — see core/push_service.dart). The file itself is committed
    // (not gitignored): it contains public app identifiers restricted by
    // package name/SHA fingerprint server-side, not secrets — this is
    // Google's own documented guidance, same as most open-source Flutter/
    // Firebase apps.
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
