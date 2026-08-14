plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase is applied only when its configuration is actually present.
//
// The alternative — declaring it unconditionally — makes `google-services.json`
// a build dependency, and anyone cloning the repo without a Firebase project of
// their own cannot build the app at all. That is the same trap the Supabase
// credentials avoid by falling back to mock mode.
//
// The cost is that a build can ship without push and say nothing, so it says
// something: `PushService.initialize()` gives up quietly at runtime, and this
// warns at build time.
val firebaseConfig = file("google-services.json")
if (firebaseConfig.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "\n" +
        "*********************************************************************\n" +
        "  android/app/google-services.json is missing.\n" +
        "  This build will run, but PUSH NOTIFICATIONS WILL BE DISABLED.\n" +
        "  Add the file from the Firebase console before shipping a release.\n" +
        "*********************************************************************\n"
    )
}

android {
    namespace = "com.chandigarhuniversity.campus_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications schedules against java.time, which is
        // not in the Android API level this app targets.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chandigarhuniversity.campus_connect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
