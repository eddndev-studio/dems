import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Las credenciales se leen de `android/key.properties`
// (NO versionado) o, en su defecto, de variables de entorno (útil en CI).
// Claves esperadas en key.properties:
//   storeFile=...   (ruta al .jks/.keystore, relativa a android/app o absoluta)
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
// Variables de entorno equivalentes (fallback):
//   DEMS_STORE_FILE, DEMS_STORE_PASSWORD, DEMS_KEY_ALIAS, DEMS_KEY_PASSWORD
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

fun signingValue(propKey: String, envKey: String): String? {
    return (keystoreProperties.getProperty(propKey) ?: System.getenv(envKey))
        ?.takeIf { it.isNotBlank() }
}

val releaseStoreFile = signingValue("storeFile", "DEMS_STORE_FILE")
val hasReleaseSigning = releaseStoreFile != null

android {
    namespace = "mx.ipn.dems.dems_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mx.ipn.dems.dems_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Sólo materializamos la config de release si hay credenciales
        // (key.properties o env vars). Sin ellas, caemos al firmado debug.
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "DEMS_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "DEMS_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "DEMS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Con credenciales reales → firma de release; si no, cae al debug
            // signing (como hasta ahora) para que `flutter run --release` siga
            // funcionando sin secretos.
            signingConfig = if (hasReleaseSigning) {
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
