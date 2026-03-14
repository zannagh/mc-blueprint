pluginManagement {
    repositories {
        maven("https://maven.fabricmc.net/")
        maven("https://maven.neoforged.net/releases/")
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.kikugie.stonecutter") version "0.8.3"
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}

stonecutter {
    kotlinController = true
    centralScript = "build.gradle.kts"

    val fabricVersions = listOf(
        "1.21.11",
    )
    val neoforgeVersions = listOf(
        "1.21.11",
    )

    // Required to have a parseable semVer for StoneCutter (26.1-snapshot.2 instead of 26.1-snapshot-2)
    // since this causes problems with snapshots higher than -snapshot-10.
    fun semver(v: String) = v.replace(Regex("snapshot-(\\d+)"), "snapshot.$1")

    create(rootProject) {
        vcsVersion = "fabric-1.21.11" // Latest stable

        branch("common") {
            fabricVersions.forEach { version("fabric-$it", semver(it)) }
            neoforgeVersions.forEach { version("neoforge-$it", semver(it)) }
        }
        branch("fabric") {
            fabricVersions.forEach { version("fabric-$it", semver(it)) }
        }
        branch("neoforge") {
            neoforgeVersions.forEach { version("neoforge-$it", semver(it)) }
        }
    }
}
