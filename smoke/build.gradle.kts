plugins {
    java
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(21))
}

repositories {
    mavenCentral()
}

// The smoke suite exercises the mod's loader-agnostic core (ExampleMod) WITHOUT booting
// Minecraft or resolving Loom: it compiles just that class straight from :common's main sources
// and validates the shipped loader metadata as plain files. Mixin classes under :common DO touch
// Minecraft, so they are excluded from this lightweight compile. This keeps the suite fast and
// dependency-light while still proving the core wiring is intact.
//
// The core is compiled by a standalone task rather than by adding common/src/main/java to the
// test source set: a shared srcDir makes IntelliJ mark that directory as a TEST root (the smoke
// module claims it), breaking the :common module in the IDE.
val coreCompileClasspath by configurations.creating

val compileCore by tasks.registering(JavaCompile::class) {
    source(rootProject.fileTree("common/src/main/java") { exclude("**/mixin/**") })
    classpath = coreCompileClasspath
    destinationDirectory.set(layout.buildDirectory.dir("classes/java/core"))
    javaCompiler.set(javaToolchains.compilerFor(java.toolchain))
}

dependencies {
    coreCompileClasspath("org.slf4j:slf4j-api:2.0.16")
    testImplementation(files(compileCore))

    testImplementation(platform("org.junit:junit-bom:6.0.1"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")

    // ExampleMod logs via SLF4J: the API compiles it, and a simple provider lets init() run
    // cleanly without the "no SLF4J providers were found" warning.
    testImplementation("org.slf4j:slf4j-api:2.0.16")
    testRuntimeOnly("org.slf4j:slf4j-simple:2.0.16")

    // Metadata invariants: parse the shipped fabric.mod.json / mixin configs (JSON) and
    // neoforge.mods.toml (TOML) the same way the loaders would.
    testImplementation("com.google.code.gson:gson:2.13.1")
    testImplementation("org.tomlj:tomlj:1.1.1")
}

tasks.named<Test>("test") {
    useJUnitPlatform()
    // Locate the shipped loader metadata relative to the repo root, independent of the CWD.
    systemProperty("smoke.repo.root", rootProject.projectDir.absolutePath)
    testLogging {
        events("passed", "skipped", "failed")
    }
}
