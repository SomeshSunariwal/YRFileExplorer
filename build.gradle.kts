// Forward workspace builds to the single, canonical Android project.
tasks.register("assembleDebug") {
    group = "build"
    description = "Build the Flutter Android debug APK."
    dependsOn(gradle.includedBuild("android").task(":app:assembleDebug"))
}
tasks.register("assembleRelease") {
    group = "build"
    description = "Build the Flutter Android release APK."
    dependsOn(gradle.includedBuild("android").task(":app:assembleRelease"))
}
