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

// Force old-style Android library plugin subprojects to compile against at least SDK 34.
// This fixes AAR metadata errors from plugins that still declare compileSdkVersion 33
// (e.g. app_settings 6.1.1) when their AndroidX dependencies require SDK 34+.
// The try-catch is intentional: newer plugins using AGP 8+ (e.g. app_links) mark compileSdk
// as immutable after DSL finalization - those plugins already target SDK 34+, so skipping them is safe.
subprojects {
    plugins.withId("com.android.library") {
        val androidComponents = extensions.findByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>()
        androidComponents?.finalizeDsl { extension ->
            if ((extension.compileSdk ?: 0) < 34) {
                extension.compileSdk = 34
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
