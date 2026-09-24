plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ph.logicclass.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time, which is only in the
        // platform from API 26. Desugaring backports it so the app can
        // still run on the older phones a school actually has.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Must match the Android app you register in the Firebase console
        // (and therefore the package in google-services.json). Change it
        // here before the first release -- it cannot be changed on the
        // Play Store afterwards.
        applicationId = "ph.logicclass.app"
        // Pinned rather than taken from flutter.minSdkVersion: firebase_auth
        // 5.x requires 23, and inheriting the Flutter default silently
        // drops below that when the SDK moves.
        //
        // Raised to 24 for jitsi_meet_flutter_sdk, whose Android SDK does
        // not support 23. That drops Android 6.0 Marshmallow, which is a
        // real cost for a school with very old handsets -- worth knowing
        // before a rollout, and the reason it is written down here rather
        // than simply bumped.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
