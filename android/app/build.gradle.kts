plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.explorer.fileexplorer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint { lintConfig = rootProject.file("lint.xml") }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.explorer.fileexplorer"
        minSdk = 31
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Development signing. Configure a private release key before distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
flutter { source = "../.." }
dependencies {
    implementation("net.lingala.zip4j:zip4j:2.11.6")
    implementation("commons-net:commons-net:3.13.0")
    implementation("com.github.mwiede:jsch:2.28.8")
    implementation("com.hierynomus:smbj:0.15.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
}
