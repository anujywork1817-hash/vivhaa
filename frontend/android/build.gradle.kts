allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. flutter_webrtc) ship with an older hardcoded
// compileSdk that's lower than what their own AndroidX dependencies
// require. Force every Android library subproject to compile against a
// modern SDK rather than patching each plugin's vendored build.gradle
// (which pub get would overwrite anyway).
subprojects {
    // :app is forced to evaluate eagerly above (evaluationDependsOn), so by
    // the time this block runs for it, calling afterEvaluate on it would
    // fail with "project already evaluated" — and it's not a library
    // module anyway, so just skip it.
    if (name != "app") {
        afterEvaluate {
            if (plugins.hasPlugin("com.android.library")) {
                extensions.configure<com.android.build.gradle.LibraryExtension> {
                    compileSdk = 36
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
