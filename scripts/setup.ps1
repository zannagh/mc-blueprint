<#
.SYNOPSIS
    mc-blueprint setup script — scaffolds a new Minecraft mod project from the template.

.DESCRIPTION
    Copies the template into a target directory, replacing all placeholders with the
    user's mod name, package, etc.

.EXAMPLE
    .\scripts\setup.ps1 -Target ~\Projects\my-mod -ModId my-mod `
        -ModName "My Mod" -Package com.example.mymod

.EXAMPLE
    .\scripts\setup.ps1 -Target ~\Projects\my-mod -ModId my-mod `
        -ModName "My Mod" -Package com.example.mymod -Kotlin
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$ModId,
    [string]$ModName,
    [Parameter(Mandatory)][string]$Package,
    [switch]$Kotlin
)

$ErrorActionPreference = 'Stop'

# ── Derive name variants ─────────────────────────────────────────────────────

if (-not $ModName) { $ModName = $ModId }

$ModIdSnake  = $ModId -replace '-', '_'
$ModIdJoined = $ModId -replace '-', ''

# PascalCase: split on - or _, capitalise each segment
$ModIdPascal = ($ModId -split '[-_]' | ForEach-Object {
    $_.Substring(0,1).ToUpper() + $_.Substring(1)
}) -join ''

$PackagePath = $Package -replace '\.', '/'

# ── Resolve paths ─────────────────────────────────────────────────────────────

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateDir = Join-Path (Split-Path -Parent $ScriptDir) 'template'

if (-not (Test-Path $TemplateDir)) {
    Write-Error "Template directory not found at $TemplateDir"
    exit 1
}

$Target = [System.IO.Path]::GetFullPath($Target)

if ((Test-Path $Target) -and (Get-ChildItem $Target -Force | Select-Object -First 1)) {
    $confirm = Read-Host "Warning: Target directory $Target is not empty. Continue? [y/N]"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

# ── Copy template ─────────────────────────────────────────────────────────────

Write-Host "Copying template to $Target ..."
if (-not (Test-Path $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }
Copy-Item -Path "$TemplateDir\*" -Destination $Target -Recurse -Force
# Also copy hidden files (.gitignore)
Get-ChildItem $TemplateDir -Force -File | Where-Object { $_.Name.StartsWith('.') } | ForEach-Object {
    Copy-Item $_.FullName -Destination $Target -Force
}

# ── Text replacements ────────────────────────────────────────────────────────

Write-Host "Applying placeholders ..."

$textExtensions = @('*.java','*.kt','*.kts','*.json','*.toml','*.properties','*.yml','*.yaml','*.xml','*.md')

Get-ChildItem $Target -Recurse -File -Include $textExtensions | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    if ($null -eq $content) { return }

    # Order matters: longer / more specific patterns first
    $content = $content -replace 'com\.example\.examplemod', $Package
    $content = $content -replace 'com/example/examplemod',   $PackagePath
    $content = $content -replace 'ExampleMod',               $ModIdPascal
    $content = $content -replace 'Example Mod',              $ModName
    $content = $content -replace 'example_mod',              $ModIdSnake
    $content = $content -replace 'example-mod',              $ModId
    $content = $content -replace 'examplemod',               $ModIdJoined

    Set-Content $_.FullName -Value $content -NoNewline
}

# ── Rename files whose names contain the placeholder ─────────────────────────

Write-Host "Renaming files ..."

Get-ChildItem $Target -Recurse -File | Where-Object { $_.Name -match 'example-mod' } | ForEach-Object {
    $newName = $_.Name -replace 'example-mod', $ModId
    Rename-Item $_.FullName -NewName $newName
}

# ── Rename Java source directories ───────────────────────────────────────────

Write-Host "Restructuring packages ..."

# Find all com/example/examplemod directories (deepest first)
Get-ChildItem $Target -Recurse -Directory | Where-Object {
    $_.FullName -match [regex]::Escape([IO.Path]::Combine('com','example','examplemod'))
} | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    $oldDir = $_.FullName
    # Find the parent above "com"
    $parent = $oldDir -replace ([regex]::Escape([IO.Path]::Combine('com','example','examplemod')) + '.*$'), ''
    $parent = $parent.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $newDir = Join-Path $parent $PackagePath.Replace('/', [IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path $newDir)) { New-Item -ItemType Directory -Path $newDir -Force | Out-Null }

    # Copy contents
    Get-ChildItem $oldDir -Force | ForEach-Object {
        Copy-Item $_.FullName -Destination $newDir -Recurse -Force
    }

    # Remove old com/example tree
    $comDir = Join-Path $parent 'com'
    if (Test-Path $comDir) { Remove-Item $comDir -Recurse -Force }
}

# ── Rename Java class files ──────────────────────────────────────────────────

Get-ChildItem $Target -Recurse -File | Where-Object { $_.Name -match '^ExampleMod' } | ForEach-Object {
    $newName = $_.Name -replace 'ExampleMod', $ModIdPascal
    Rename-Item $_.FullName -NewName $newName
}

# ── Kotlin support ───────────────────────────────────────────────────────────

if ($Kotlin) {
    Write-Host "Adding Kotlin language support ..."

    $KotlinVersion              = '2.1.20'
    $FabricLangKotlinVersion    = "1.13.1+kotlin.$KotlinVersion"
    $KotlinForForgeVersion      = '5.6.0'

    # 1. Add Kotlin Gradle plugin to buildSrc
    $buildSrc = Join-Path $Target 'buildSrc' 'build.gradle.kts'
    $buildSrcContent = Get-Content $buildSrc -Raw
    $buildSrcContent = $buildSrcContent -replace '(implementation\("net\.fabricmc:fabric-loom)',
        "implementation(`"org.jetbrains.kotlin:kotlin-gradle-plugin:$KotlinVersion`")`n    `$1"
    Set-Content $buildSrc -Value $buildSrcContent -NoNewline

    # 2. Create kotlin-support convention plugin
    $kotlinPlugin = Join-Path $Target 'buildSrc' 'src' 'main' 'kotlin' 'kotlin-support.gradle.kts'
    @'
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(findProperty("java.version")?.toString()?.toInt() ?: 21)
}
'@ | Set-Content $kotlinPlugin -NoNewline

    # 3. Apply kotlin-support in module build scripts
    foreach ($buildFile in @(
        (Join-Path $Target 'common' 'build.gradle.kts'),
        (Join-Path $Target 'fabric' 'build.gradle.kts'),
        (Join-Path $Target 'neoforge' 'build.gradle.kts')
    )) {
        $c = Get-Content $buildFile -Raw
        $c = $c -replace '(plugins \{)', "`$1`n    id(`"kotlin-support`")"
        Set-Content $buildFile -Value $c -NoNewline
    }

    # 4. Add fabric-language-kotlin to fabric
    $fabricBuild = Join-Path $Target 'fabric' 'build.gradle.kts'
    $c = Get-Content $fabricBuild -Raw
    $c = $c -replace '(modImplementation.*?fabric-loader.*?\))',
        "`$1`n    add(`"modImplementation`", `"net.fabricmc:fabric-language-kotlin:$FabricLangKotlinVersion`")"
    Set-Content $fabricBuild -Value $c -NoNewline

    # 5. Update fabric.mod.json depends
    $fabricJson = Join-Path $Target 'fabric' 'src' 'main' 'resources' 'fabric.mod.json'
    $c = Get-Content $fabricJson -Raw
    $c = $c -replace '"fabricloader": ">=0.15.0"',
        "`"fabricloader`": `">=0.15.0`",`n    `"fabric-language-kotlin`": `">=$FabricLangKotlinVersion`""
    Set-Content $fabricJson -Value $c -NoNewline

    # 6. Add KotlinForForge to neoforge
    $neoforgeBuild = Join-Path $Target 'neoforge' 'build.gradle.kts'
    $c = Get-Content $neoforgeBuild -Raw
    $c = $c -replace '(^neoForge \{)', "repositories {`n    maven(`"https://thedarkcolour.github.io/KotlinForForge/`")`n}`n`n`$1"
    $c += "`n`ndependencies {`n    implementation(`"thedarkcolour:kotlinforforge-neoforge:$KotlinForForgeVersion`")`n}`n"
    Set-Content $neoforgeBuild -Value $c -NoNewline

    # 7. Update neoforge.mods.toml loader
    $neoforgeToml = Join-Path $Target 'neoforge' 'src' 'main' 'resources' 'META-INF' 'neoforge.mods.toml'
    $c = Get-Content $neoforgeToml -Raw
    $c = $c -replace 'modLoader="javafml"', 'modLoader="kotlinforforge"'
    Set-Content $neoforgeToml -Value $c -NoNewline

    Write-Host "Kotlin support enabled."
}

# ── Initialise git ───────────────────────────────────────────────────────────

$isGitRepo = $false
try { git -C $Target rev-parse --is-inside-work-tree 2>$null | Out-Null; $isGitRepo = $true } catch {}

if (-not $isGitRepo) {
    Write-Host "Initialising git repository ..."
    git -C $Target init -b main
    git -C $Target add .
    git -C $Target commit -m "Initial project from mc-blueprint template"
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Your mod project is ready at: $Target"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open the project in IntelliJ IDEA"
Write-Host "  2. Let Gradle sync complete"
Write-Host "  3. Start coding in common/src/main/java/..."
Write-Host ""
Write-Host "Useful Gradle tasks:"
Write-Host "  ./gradlew build                    Build the active version"
Write-Host "  ./gradlew stageArtifacts           Build all versions and stage JARs"
Write-Host '  ./gradlew "Set active project to neoforge-1.21.11"'
