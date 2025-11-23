plugins {
    alias(libs.plugins.android.application)
    // Firebase 插件（之後會加入）
    // id("com.google.gms.google-services")
}

android {
    namespace = "com.example.smartbadmintonracket"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.example.smartbadmintonracket"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(libs.appcompat)
    implementation(libs.material)
    implementation(libs.activity)
    implementation(libs.constraintlayout)
    
    // BLE 支援（使用 Android 原生 BLE API）
    // 不需要額外依賴，使用 android.bluetooth 套件
    
    // Gson (用於 JSON 序列化/反序列化，校正資料儲存)
    implementation("com.google.code.gson:gson:2.10.1")
    
    // Firebase（之後會加入）
    // implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    // implementation("com.google.firebase:firebase-firestore")
    
    testImplementation(libs.junit)
    androidTestImplementation(libs.ext.junit)
    androidTestImplementation(libs.espresso.core)
}