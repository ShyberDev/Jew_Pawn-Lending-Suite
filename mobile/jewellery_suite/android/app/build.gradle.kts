import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// #027/#028: release builds are signed with the shop's own keystore, read from
// android/key.properties. Both files are gitignored and must be backed up —
// losing the keystore means Play cannot accept an update.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// Never fall back to the debug key. Any task whose name contains "Release"
// (assembleRelease, bundleRelease, …) stops here unless the key file is present,
// complete, and points at a real keystore. Debug builds are unaffected.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.name.contains("Release") }) return@whenReady
    if (!hasReleaseKeystore) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing.\n" +
                "Create it with storePassword, keyPassword, keyAlias and storeFile, " +
                "and keep the .jks file backed up."
        )
    }
    val required = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    val missing = required.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties is incomplete — missing: ${missing.joinToString()}"
        )
    }
    val store = file(keystoreProperties.getProperty("storeFile"))
    if (!store.exists()) {
        throw GradleException("Release keystore not found at ${store.path}")
    }
}

android {
    namespace = "com.shyberdev.jewellery_suite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.shyberdev.jewellery_suite"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release") else null
            // R8 rules live in proguard-rules.pro (Flutter wrapper + the ML Kit
            // Latin-only text-recognition dontwarn rules).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
