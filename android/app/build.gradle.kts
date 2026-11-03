import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = file(System.getenv("REELBOX_SIGNING_PROPERTIES")
    ?: "${System.getProperty("user.home")}/.config/reelbox-signing/keystore.properties")
val signingProperties = Properties().apply {
    if (signingFile.isFile) signingFile.inputStream().use { load(it) }
}

android {
    signingConfigs {
        create("release") {
            if (signingFile.isFile) {
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    namespace = "org.reelbox.reelbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Dependency release-lint analysis exceeded this host's memory/time budget.
    // Run Android lint separately on a larger machine before store distribution.
    lint {
        checkReleaseBuilds = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.reelbox.app"
        // This delivery targets ARM64. Exclude dependency-only ABIs that lack
        // Flutter's libapp/libflutter and would falsely advertise support.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24) // Native default-network callback / scoped media lifecycle.
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
            // Missing release keys fail closed; never use Android's debug signer.
            signingConfig = signingConfigs.getByName("release")
            // Keep Dart AOT release mode; avoid the Java R8/resource shrinker
            // on the constrained build host. This increases APK size.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Google currently documents 23.0.0, but its MediaRouter 1.9 beta requires
    // compileSdk 37. Use verified 22.3.1 on this repository's installed SDK 35.
    implementation("com.google.android.gms:play-services-cast-framework:22.3.1")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.mediarouter:mediarouter:1.8.1")
}

flutter {
    source = "../.."
}
