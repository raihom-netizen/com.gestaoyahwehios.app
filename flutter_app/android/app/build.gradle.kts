import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gestaoyahweh.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.gestaoyahweh.app"
        // Android 5.0+ (API 21); API 23+ para biometria (local_auth)
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val alias = keystoreProperties.getProperty("keyAlias")?.trim().orEmpty()
                val keyPass = keystoreProperties.getProperty("keyPassword")?.trim().orEmpty()
                val storePass = keystoreProperties.getProperty("storePassword")?.trim().orEmpty()
                val storePath = keystoreProperties.getProperty("storeFile")?.trim().orEmpty()
                require(alias.isNotEmpty() && keyPass.isNotEmpty() && storePass.isNotEmpty() && storePath.isNotEmpty()) {
                    "android/key.properties: preencha keyAlias, keyPassword, storePassword e storeFile (veja key.properties.example)."
                }
                keyAlias = alias
                keyPassword = keyPass
                storePassword = storePass
                storeFile = rootProject.file(storePath)
            }
        }
    }

    buildTypes {
        release {
            // Com key.properties: assinatura release (Play Store). Sem: debug — a Play rejeita.
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
