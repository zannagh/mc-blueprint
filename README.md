# mc-blueprint

A template for Minecraft mods that handles multiple loaders (Fabric + NeoForge) and game versions via [Stonecutter](https://stonecutter.kikugie.dev/), with automatic versioning via [GitVersion](https://gitversion.net/) and artifact staging for deployment.

## Quick start

Clone this repo and run the setup script to scaffold a new mod project:

```bash
# Bash (macOS / Linux)
./scripts/setup.sh \
    --target ~/Projects/my-mod \
    --mod-id my-mod \
    --mod-name "My Mod" \
    --package com.example.mymod
```

```powershell
# PowerShell (Windows)
.\scripts\setup.ps1 `
    -Target ~\Projects\my-mod `
    -ModId my-mod `
    -ModName "My Mod" `
    -Package com.example.mymod
```

Add `--kotlin` (bash) or `-Kotlin` (PowerShell) to enable Kotlin language support with `fabric-language-kotlin` and `KotlinForForge`.

## What you get

- **Multi-loader**: Fabric and NeoForge from a single codebase
- **Multi-version**: Stonecutter-powered version switching with per-version properties
- **Shared common module**: Loader-agnostic code in `common/`, automatically inherited by loaders
- **Split environments**: Separate `main` and `client` source sets
- **Automatic versioning**: GitVersion-based semantic versioning from commit messages
- **Artifact staging**: `./gradlew stageArtifacts` builds all variants and collects JARs
- **Gradle convention plugins**: Clean build logic in `buildSrc/` (no copy-paste)

## Project structure

```
your-mod/
├── buildSrc/                  Convention plugins (multiloader-common, multiloader-loader, loom-*)
├── common/                    Loader-agnostic shared code
│   ├── src/main/java/         Server + common code
│   ├── src/client/java/       Client-only code
│   └── versions/              Per-version gradle.properties
├── fabric/                    Fabric loader-specific code
│   ├── src/main/java/         Fabric entry points
│   ├── src/client/java/       Fabric client entry points
│   └── versions/              Per-version gradle.properties
├── neoforge/                  NeoForge loader-specific code
│   ├── src/main/java/         NeoForge entry points
│   └── versions/              Per-version gradle.properties
├── settings.gradle.kts        Stonecutter version matrix
├── stonecutter.gradle.kts     Active version + stageArtifacts task
└── gradle.properties          Shared mod properties
```

## Adding a new Minecraft version

1. Add the version to `fabricVersions` and/or `neoforgeVersions` in `settings.gradle.kts`
2. Create the version's `gradle.properties` under each branch's `versions/` directory
3. Sync Gradle

## Switching the active version

```bash
./gradlew "Set active project to neoforge-1.21.11"
```

Then re-sync in IntelliJ.

## Version bumps

Use commit message prefixes:
- `+semver: major` or `+semver: breaking` — major bump
- `+semver: minor` or `+semver: feature` — minor bump
- `+semver: patch` or `+semver: fix` — patch bump
- `+semver: none` or `+semver: skip` — no bump
