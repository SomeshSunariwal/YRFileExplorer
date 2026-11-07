import com.somesh.yrfileexplorer.gradle.AndroidRpcTransform
import org.gradle.api.attributes.Attribute
import org.gradle.api.artifacts.type.ArtifactTypeDefinition

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.somesh.yrfileexplorer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint { lintConfig = rootProject.file("lint.xml") }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.somesh.yrfileexplorer"
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
// Only DCERPC needs its Java SE exception reference adapted for Android.
val androidRpc = Attribute.of("com.somesh.yrfileexplorer.android-rpc", Boolean::class.javaObjectType)
configurations.configureEach {
    if (isCanBeResolved) attributes.attribute(androidRpc, true)
}
dependencies {
    implementation("org.bouncycastle:bcprov-jdk18on:1.85.2")
    implementation("com.google.crypto.tink:tink-android:1.23.0")
    artifactTypes.getByName("jar").attributes.attribute(androidRpc, false)
    registerTransform(AndroidRpcTransform::class.java) {
        from.attribute(androidRpc, false)
            .attribute(ArtifactTypeDefinition.ARTIFACT_TYPE_ATTRIBUTE, "jar")
        to.attribute(androidRpc, true)
            .attribute(ArtifactTypeDefinition.ARTIFACT_TYPE_ATTRIBUTE, "jar")
    }
    implementation("net.lingala.zip4j:zip4j:2.11.6")
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
    implementation("commons-net:commons-net:3.13.0")
    implementation("com.github.mwiede:jsch:2.28.8")
    implementation("com.hierynomus:smbj:0.15.0")
    implementation("com.rapid7.client:dcerpc:0.12.13")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
}
