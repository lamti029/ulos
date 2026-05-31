plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Required so google-services.json generates Firebase Android resources (values.xml).
    id("com.google.gms.google-services") version "4.4.4"
}

dependencies {
    // Required by some AARs (e.g. flutter_local_notifications) that need core library desugaring.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.13.0"))

    // Add the dependencies for Firebase products you want to use
    implementation("com.google.firebase:firebase-analytics")
}

android {
    namespace = "com.bps.ulos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by some AARs (e.g. flutter_local_notifications) that need core library desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        @Suppress("DEPRECATION")
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.bps.ulos"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // Force native libraries to be properly packed & compressed
        // so ReLinker and older/modern devices can extract libflutter.so correctly.
        packaging {
            jniLibs {
                useLegacyPackaging = true
            }
        }

        // ABI filtering to reduce APK size.
        // If you only target arm64 devices, you can remove the v7a line.
        ndk {
            // Target only arm64 to aggressively reduce APK size.
            abiFilters += listOf("arm64-v8a")
        }


    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Size optimizations (R8) + resource shrinking.
            // Size optimizations: enable R8 (code shrinking) and resource shrinking.
            // If R8 reports missing classes, add keep rules from missing_rules.txt.
            isMinifyEnabled = true
            isShrinkResources = true



            // Keep proguardFiles for potential future enabling minify.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }


    }

    applicationVariants.all {
        val variant = this
        variant.outputs.map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }.forEach { output ->
            output.outputFileName = "ulos_${variant.versionName}.apk"
        }
    }
}

flutter {
    source = "../.."
}