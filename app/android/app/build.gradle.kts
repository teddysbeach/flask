import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 키. 저장소에는 없다(.gitignore).
// android/key.properties 가 있으면 그걸로 서명하고, 없으면 디버그 키로 떨어진다 —
// CI 와 새로 받은 클론에서 `flutter build apk` 가 그냥 되게 하려는 것이다.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "me.popol.onpar"

    // Flutter 3.35 기본값. flutter_timezone 이 35 이상을 요구하므로 내리면 안 된다.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications 는 java.time 을 쓴다. minSdk 24 에서는 그게 없으므로
        // 디슈가링이 없으면 복습 알림 예약이 런타임에 죽는다.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "me.popol.onpar"

        // ── minSdk 24 (Android 7.0) ──────────────────────────────────────
        // 의존성이 요구하는 값 중 가장 높은 것이다. 취향이 아니라 계산 결과다.
        //   image_picker_android 0.8.13+17      → 24
        //   url_launcher_android 6.3.29         → 24
        //   shared_preferences_android 2.4.23   → 24
        //   in_app_purchase_android 0.4.0+10    → 21
        //   flutter_inappwebview_android 1.1.3  → 19
        // Flutter 3.35 의 기본 minSdk 도 24 라 결과가 같다. 하나라도 올리면 여기도 올라간다.
        minSdk = 24

        // 정책상 최신을 따라간다(Play 는 신규·업데이트 APK 에 최신 targetSdk 를 요구한다).
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKeystore) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
