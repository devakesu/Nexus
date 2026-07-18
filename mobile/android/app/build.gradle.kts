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

// Load local.properties
val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.exists()) {
    localProperties.load(localPropertiesFile.inputStream())
}
val mapsApiKey = localProperties.getProperty("mapsApiKey") ?: "YOUR_GOOGLE_MAPS_API_KEY_HERE"

android {
    namespace = "com.devakesu.apps.nexus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.devakesu.apps.nexus"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }
    
    flavorDimensions += "brand"

    productFlavors {
        create("nexus") {
            dimension = "brand"
            applicationId = "com.devakesu.apps.nexus"
            resValue("string", "app_name", "Nexus")
            manifestPlaceholders["appScheme"] = "devakesu-nexus"
            manifestPlaceholders["appHost"] = "nexus.devakesu.com"
            // Spotify Auth Library redirect URI: devakesu-nexus://spotify-auth
            manifestPlaceholders["redirectSchemeName"] = "devakesu-nexus"
            manifestPlaceholders["redirectHostName"] = "spotify-auth"
        }
        create("mec") {
            dimension = "brand"
            applicationId = "com.devakesu.apps.nexus.mec"
            resValue("string", "app_name", "Nexus MEC")
            manifestPlaceholders["appScheme"] = "devakesu-nexus-mec"
            manifestPlaceholders["appHost"] = "nexus-mec.devakesu.com"
            // Spotify Auth Library redirect URI: devakesu-nexus-mec://spotify-auth
            manifestPlaceholders["redirectSchemeName"] = "devakesu-nexus-mec"
            manifestPlaceholders["redirectHostName"] = "spotify-auth"
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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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

// firebase-iid is fully superseded by firebase-messaging; exclude it to prevent
// duplicate class errors when transitive deps (e.g. Spotify auth) pull it in.
configurations.all {
    exclude(group = "com.google.firebase", module = "firebase-iid")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Spotify Android Auth Library - provides native SSO when the Spotify app is installed,
    // falls back to Chrome Custom Tabs otherwise. Register your SHA-1 fingerprints and
    // both redirect URIs in the Spotify Developer Dashboard.
    implementation("com.spotify.android:auth:2.1.0")
}
