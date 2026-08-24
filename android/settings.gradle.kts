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
    id("com.android.application") version "9.1.0" apply false
    // Flutter's dependency validator still reads this version with built-in
    // Kotlin enabled. `apply false` keeps the legacy plugin disabled.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// Flutter 3.47.1 scans plugin build files as plain text and incorrectly treats
// guarded KGP fallbacks as unconditional KGP usage. Evaluate the original
// scripts through small wrappers until flutter/flutter#189770 is fixed.
mapOf(
    "mobile_scanner" to "flutter_plugin_wrappers/mobile_scanner.gradle",
    "workmanager_android" to "flutter_plugin_wrappers/workmanager_android.gradle",
).forEach { (pluginName, wrapperPath) ->
    val pluginProject = project(":$pluginName")
    pluginProject.buildFileName =
        pluginProject.projectDir
            .toPath()
            .relativize(rootDir.resolve(wrapperPath).toPath())
            .toString()
}
