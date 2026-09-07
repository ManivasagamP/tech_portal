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
// Flutter plugins (e.g. jni) declare `ndkVersion flutter.ndkVersion`, which points at an NDK
// release this machine has only a partial download of. Pin every Android subproject to the NDK
// the app module already uses. Must be registered before the evaluationDependsOn block below,
// which eagerly evaluates :app and would make afterEvaluate illegal for it.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("ndkVersion", "30.0.16138531")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
