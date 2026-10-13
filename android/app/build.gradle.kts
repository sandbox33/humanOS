plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from the android.yml job: KEYSTORE_PATH points to the
// decrypted upload key and KEYSTORE_PASSWORD protects store and key (alias
// "upload"). Without them the build falls back to the debug key; such APKs
// are CI checks only and are never published.
val keystorePath: String? = System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val keystorePassword: String? = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
val hasReleaseKey = keystorePath != null && keystorePassword != null && file(keystorePath).exists()

android {
    namespace = "com.altair.humanos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.altair.humanos"
        // Health Connect needs Android 8.0 (API 26) or newer.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = "upload"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
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

dependencies {
    // Version required by flutter_local_notifications (see its README).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
