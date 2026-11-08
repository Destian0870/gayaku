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

// Plugins written against older Android Gradle Plugin versions pin Java to 11
// and leave Kotlin's target unset, so Kotlin defaults to the running JDK (24 on
// this machine) and AGP 9 refuses the mismatch. Align every plugin module on 17,
// which is what the app module already compiles at. This has to run after each
// module's own build script, because that script sets its Java level while being
// evaluated — and Flutter's plugin loader has already evaluated some modules by
// the time this runs, hence the two branches.
subprojects {
    fun alignJvmTargets(project: Project) {
        if (project.plugins.hasPlugin("com.android.library")) {
            project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        project.tasks
            .withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
    }
    if (state.executed) {
        alignJvmTargets(this)
    } else {
        afterEvaluate { alignJvmTargets(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
