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

// Compile file_picker's Kotlin, which nothing else does.
//
// Under AGP 9 the plugin deliberately does not apply the Kotlin Gradle
// Plugin -- it branches on the AGP version and expects AGP's built-in
// Kotlin to take over:
//
//     if (!isAgp9OrAbove) { apply plugin: 'org.jetbrains.kotlin.android' }
//
// But built-in Kotlin is off here: the Flutter template ships
// android.builtInKotlin=false, and instead the Flutter Gradle Plugin
// applies kotlin-android to every plugin module that does not apply it
// itself. It decides which those are by matching a regex against the
// build file's *text*, so it sees the apply line above -- dead branch and
// all -- assumes file_picker handles its own Kotlin, and skips it.
//
// Both sides step back, so nobody compiles FilePickerPlugin.kt and the
// generated registrant fails to link against a class that was never
// built:
//
//     GeneratedPluginRegistrant.java:39: error: cannot find symbol
//       new com.mr.flutter.plugin.filepicker.FilePickerPlugin()
//
// This is the same call the Flutter Gradle Plugin would have made, aimed
// at the one module its detection misses. Applying a plugin twice is a
// no-op, so this stays correct if file_picker's condition flips back or
// Flutter's detection learns to evaluate it.
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                pluginManager.apply("org.jetbrains.kotlin.android")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
