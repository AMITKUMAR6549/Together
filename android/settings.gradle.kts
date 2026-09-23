try {
    val processEnvClass = Class.forName("java.lang.ProcessEnvironment")
    val envField = processEnvClass.getDeclaredField("theEnvironment")
    envField.isAccessible = true
    @Suppress("UNCHECKED_CAST")
    val env = envField.get(null) as MutableMap<String, String>
    env.remove("ANDROID_PREFS_ROOT")
    env.remove("ANDROID_SDK_HOME")

    val unenvField = processEnvClass.getDeclaredField("theUnmodifiableEnvironment")
    unenvField.isAccessible = true
    @Suppress("UNCHECKED_CAST")
    val unenv = unenvField.get(null) as MutableMap<String, String>
    unenv.remove("ANDROID_PREFS_ROOT")
    unenv.remove("ANDROID_SDK_HOME")
} catch (_: Exception) {}
System.clearProperty("ANDROID_PREFS_ROOT")
System.clearProperty("ANDROID_SDK_HOME")

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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

include(":app")
