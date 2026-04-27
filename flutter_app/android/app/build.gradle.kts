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
var hasValidReleaseKeystore = false
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    val alias = keystoreProperties.getProperty("keyAlias")?.trim().orEmpty()
    val keyPass = keystoreProperties.getProperty("keyPassword")?.trim().orEmpty()
    val storePass = keystoreProperties.getProperty("storePassword")?.trim().orEmpty()
    val storePath = keystoreProperties.getProperty("storeFile")?.trim().orEmpty()
    if (alias.isNotEmpty() && keyPass.isNotEmpty() && storePass.isNotEmpty() && storePath.isNotEmpty()) {
        val storeFile = rootProject.file(storePath)
        hasValidReleaseKeystore = storeFile.isFile
    }
}

android {
    namespace = "com.gestaoyahweh.app"
    compileSdk = 36
    // 16KB memory page size (Android 15+; Play exige a partir de Nov/2025): o NDK r28+ gera
    // bibliotecas nativas com alinhamento ELF 16K. Não depender de flutter.ndkVersion, que
    // em muitas instalações ainda é r26/r27. @see https://developer.android.com/guide/practices/page-sizes
    ndkVersion = "28.0.13004108"

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
        // Publicamos apenas arm64-v8a para eliminar binarios 32-bit legados (ex.: pdfium armeabi-v7a)
        // que ainda podem vir com alinhamento 4KB e serem rejeitados pela Play no requisito 16KB.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasValidReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")!!.trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")!!.trim()
                storePassword = keystoreProperties.getProperty("storePassword")!!.trim()
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile")!!.trim())
            }
        }
    }

    buildTypes {
        release {
            // Play App Signing: Google re-assina depois, mas o .aab tem de vir assinado com a chave de UPLOAD (release).
            // Sem keystore valido, o Gradle falha aqui em vez de gerar bundle DEBUG (rejeitado pela Play).
            check(hasValidReleaseKeystore) {
                "Gestao YAHWEH: falta android/key.properties + .jks de release validos. " +
                    "Sem isso o AAB seria assinado em DEBUG e a Play Console rejeita. " +
                    "Na raiz do repo: .\\scripts\\build_android_play_store_aab.ps1"
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // Evita :app:lintVitalAnalyzeRelease a bloquear ficheiros no Windows (antivírus/IDE).
    lint {
        checkReleaseBuilds = false
    }

    // Com AGP 8.5.1+ (settings.gradle.kts), empacotamento moderno: zip alignment 16K para .so
    // não comprimidos — alinhado ao requisito Google Play 16K.
    packaging {
        jniLibs {
            useLegacyPackaging = false
            excludes += setOf("**/armeabi-v7a/libpdfium.so")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Play / Android 15: enableEdgeToEdge() em MainActivity (activity-ktx 1.8+).
    implementation("androidx.activity:activity-ktx:1.9.3")
}
