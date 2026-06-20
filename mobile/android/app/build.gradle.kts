import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


// Load key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.devakesu.apps.nexus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.devakesu.apps.nexus"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    
    flavorDimensions += "brand"

    productFlavors {
        create("nexus") {
            dimension = "brand"
            applicationId = "com.devakesu.apps.nexus"
            resValue("string", "app_name", "Nexus")
            manifestPlaceholders["appScheme"] = "devakesu-nexus"
            manifestPlaceholders["appHost"] = "nexus.devakesu.com"
        }
        create("mec") {
            dimension = "brand"
            applicationId = "com.devakesu.apps.nexus.mec"
            resValue("string", "app_name", "Nexus MEC")
            manifestPlaceholders["appScheme"] = "devakesu-nexus-mec"
            manifestPlaceholders["appHost"] = "nexus-mec.devakesu.com"
        }
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProperties.getProperty("storeFile") ?: "release_upload.p12"
            val keystoreFile = rootProject.file(storePath)
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
        getByName("debug") {
            val storePath = keystoreProperties.getProperty("storeFile") ?: "release_upload.p12"
            val keystoreFile = rootProject.file(storePath)
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
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
