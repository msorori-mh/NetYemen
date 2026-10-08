import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// توقيع الإنتاج إلزامي: يُقرأ من owner_app/android/key.properties (غير مرفوع
// إلى git) أو من متغيرات البيئة WASELNET_OWNER_UPLOAD_*. بناء release بدون
// مفتاح يفشل صراحةً ولا يعود أبداً إلى مفتاح debug. بناء debug لا يحتاج مفتاحاً.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    return keystoreProperties.getProperty(propertyName)
        ?: System.getenv(environmentName)
}

val releaseStoreFile = releaseSigningValue(
    "storeFile",
    "WASELNET_OWNER_UPLOAD_STORE_FILE",
)
val releaseStorePassword = releaseSigningValue(
    "storePassword",
    "WASELNET_OWNER_UPLOAD_STORE_PASSWORD",
)
val releaseKeyAlias = releaseSigningValue(
    "keyAlias",
    "WASELNET_OWNER_UPLOAD_KEY_ALIAS",
)
val releaseKeyPassword = releaseSigningValue(
    "keyPassword",
    "WASELNET_OWNER_UPLOAD_KEY_PASSWORD",
)
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested && !hasReleaseSigning) {
    throw GradleException(
        "Release signing is required. Configure owner_app/android/key.properties " +
            "or WASELNET_OWNER_UPLOAD_* environment variables.",
    )
}

android {
    namespace = "com.netyemen.owner"
    compileSdk = 36
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
        applicationId = "com.netyemen.owner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
