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

// AGP is held on 8.x deliberately.
//
// The Flutter template that generated this project moved to AGP 9, and under
// AGP 9 the Kotlin classes of any plugin that applies the Kotlin Gradle Plugin
// itself - file_picker, flutter_timezone and package_info_plus here - are not
// on the classpath when the app's own Java is compiled. The build fails on
// GeneratedPluginRegistrant.java with "cannot find symbol: FilePickerPlugin",
// which reads like a stale generated file and is not one; regenerating it
// produces the same thing. 8.9.1 rather than any 8.x because androidx.core
// 1.17 refuses to be consumed by anything older, and 8.11.1 because that is
// the floor this Flutter asks for.
//
// Move to 9 when those plugins have migrated off their own KGP - the build
// warns about each of them by name, so the list above is checkable rather than
// having to be remembered.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
