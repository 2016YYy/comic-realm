import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------------------------
// 签名配置
//
// 为了保证 CI 与本地都能拿到同一份密钥，而无需把密钥与口令提交进仓库，
// 签名信息按如下优先级读取（取到即止）：
//   1. 环境变量  COMICREALM_STORE_FILE / COMICREALM_STORE_PASSWORD /
//                  COMIC_REALM_KEY_ALIAS / COMIC_REALM_KEY_PASSWORD
//      —— CI（GitHub Actions Secrets）与本地 shell 均适用；
//   2. android/key.properties（已加入 .gitignore，仅本地存在）
//      —— 本地开发一次性写入，随后交给 IDE 读取。
//
// 两者都取不到时退化为未签名构建，并给出显式警告，不会静默产出
// 被 debug 密钥签名的「发布包」（避免 1.0.0 ~ 1.0.3 的签名分裂重演）。
// -----------------------------------------------------------------------------

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingConfigProperty(
    envName: String,
    propName: String,
): String? {
    val fromEnv = System.getenv(envName)
    if (!fromEnv.isNullOrBlank()) return fromEnv
    val fromProps = keystoreProperties.getProperty(propName)
    return if (fromProps.isNullOrBlank()) null else fromProps
}

val releaseStoreFile = signingConfigProperty("COMICREALM_STORE_FILE", "storeFile")
val releaseStorePassword = signingConfigProperty("COMICREALM_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingConfigProperty("COMIC_REALM_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingConfigProperty("COMIC_REALM_KEY_PASSWORD", "keyPassword")

val hasCompleteSigning = !releaseStoreFile.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.comicrealm.comic_realm"
    // background_downloader 要求以 Android SDK 36 编译，故此处不再跟随 Flutter 默认值。
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.comicrealm.comic_realm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // background_downloader 要求 minSdk ≥ 23，故此处不再跟随 Flutter 默认值
        // （Flutter 3.29 的 flutter.minSdkVersion 仍是 21，会触发 Manifest 合并失败）。
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCompleteSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
            logger.lifecycle("[comic-realm] release 签名已从环境变量 / key.properties 载入")
        } else {
            logger.warn(
                "[comic-realm] 未找到签名配置。" +
                    "release 包将不带正式签名，" +
                    "发布前请设置 COMICREALM_* 环境变量或生成 android/key.properties。"
            )
        }
    }

    buildTypes {
        release {
            if (hasCompleteSigning) {
                // 使用统一发布签名证书，确保后续版本升级时签名一致。
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
