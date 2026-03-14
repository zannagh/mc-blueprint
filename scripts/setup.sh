#!/usr/bin/env bash
set -euo pipefail

# ── mc-blueprint setup script ──────────────────────────────────────────────────
# Copies the template into a target directory, replacing all placeholders with
# the user's mod name, package, etc.
#
# Usage:
#   ./scripts/setup.sh --target ~/Projects/my-mod --mod-id my-mod \
#       --mod-name "My Mod" --package com.example.mymod [--kotlin]

# ── Argument parsing ──────────────────────────────────────────────────────────

TARGET=""
MOD_ID=""
MOD_NAME=""
PACKAGE=""
KOTLIN=false

usage() {
    cat <<EOF
Usage: $0 --target <dir> --mod-id <id> --mod-name <name> --package <pkg> [--kotlin]

Arguments:
  --target   Target directory for the new project (required)
  --mod-id   Mod identifier in kebab-case, e.g. "my-cool-mod" (required)
  --mod-name Display name, e.g. "My Cool Mod" (defaults to mod-id)
  --package  Java/Kotlin package, e.g. "com.example.mycoolmod" (required)
  --kotlin   Enable Kotlin language support (adds fabric-language-kotlin / KotlinForForge)
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)  TARGET="$2";   shift 2;;
        --mod-id)  MOD_ID="$2";   shift 2;;
        --mod-name) MOD_NAME="$2"; shift 2;;
        --package) PACKAGE="$2";  shift 2;;
        --kotlin)  KOTLIN=true;   shift;;
        -h|--help) usage;;
        *) echo "Unknown argument: $1"; usage;;
    esac
done

[[ -z "$TARGET" ]]  && echo "Error: --target is required"  && usage
[[ -z "$MOD_ID" ]]  && echo "Error: --mod-id is required"  && usage
[[ -z "$PACKAGE" ]] && echo "Error: --package is required"  && usage
[[ -z "$MOD_NAME" ]] && MOD_NAME="$MOD_ID"

# ── Derive name variants ─────────────────────────────────────────────────────

MOD_ID_SNAKE="${MOD_ID//-/_}"
MOD_ID_JOINED="${MOD_ID//-/}"

# PascalCase conversion (split on - or _, capitalise each segment)
to_pascal() {
    local result=""
    local IFS='-_'
    for word in $1; do
        result+="$(tr '[:lower:]' '[:upper:]' <<< "${word:0:1}")${word:1}"
    done
    echo "$result"
}
MOD_ID_PASCAL="$(to_pascal "$MOD_ID")"

PACKAGE_PATH="${PACKAGE//\.//}"

# ── Portable sed-in-place ─────────────────────────────────────────────────────

if [[ "$(uname)" == "Darwin" ]]; then
    sedi() { sed -i '' "$@"; }
else
    sedi() { sed -i "$@"; }
fi

# ── Resolve paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../template"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: Template directory not found at $TEMPLATE_DIR"
    exit 1
fi

if [[ -d "$TARGET" ]] && [[ "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
    echo "Warning: Target directory $TARGET is not empty."
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# ── Copy template ─────────────────────────────────────────────────────────────

echo "Copying template to $TARGET ..."
mkdir -p "$TARGET"
cp -a "$TEMPLATE_DIR"/. "$TARGET"/

# ── Text replacements ────────────────────────────────────────────────────────

echo "Applying placeholders ..."

# Collect all text files that could contain placeholders
find "$TARGET" -type f \( \
    -name "*.java" -o -name "*.kt" -o -name "*.kts" -o \
    -name "*.json" -o -name "*.toml" -o -name "*.properties" -o \
    -name "*.yml" -o -name "*.yaml" -o -name "*.xml" -o -name "*.md" \
\) | while IFS= read -r file; do
    # Order matters: longer / more specific patterns first
    sedi \
        -e "s|com\.example\.examplemod|${PACKAGE}|g" \
        -e "s|com/example/examplemod|${PACKAGE_PATH}|g" \
        -e "s|ExampleMod|${MOD_ID_PASCAL}|g" \
        -e "s|Example Mod|${MOD_NAME}|g" \
        -e "s|example_mod|${MOD_ID_SNAKE}|g" \
        -e "s|example-mod|${MOD_ID}|g" \
        -e "s|examplemod|${MOD_ID_JOINED}|g" \
        "$file"
done

# ── Rename files whose names contain the placeholder ─────────────────────────

echo "Renaming files ..."

# Mixin JSON files
find "$TARGET" -type f -name "example-mod*" | while IFS= read -r old; do
    new="${old//example-mod/$MOD_ID}"
    [[ "$old" != "$new" ]] && mv "$old" "$new"
done

# ── Rename Java source directories ───────────────────────────────────────────

echo "Restructuring packages ..."

# Move every com/example/examplemod tree to the new package path
find "$TARGET" -type d -path "*/com/example/examplemod" | sort -r | while IFS= read -r old_dir; do
    # Build the new directory under the same parent of "com"
    parent="$(echo "$old_dir" | sed "s|/com/example/examplemod$||")"
    new_dir="$parent/$PACKAGE_PATH"
    mkdir -p "$new_dir"
    # Move contents (not the directory itself, in case subpackages like /client exist)
    cp -a "$old_dir"/. "$new_dir"/
    # Remove the old com/example/examplemod (and empty parents)
    rm -rf "$parent/com/example"
    # Clean up com/ if empty
    rmdir "$parent/com" 2>/dev/null || true
done

# ── Rename Java class files ──────────────────────────────────────────────────

find "$TARGET" -type f -name "ExampleMod*" | while IFS= read -r old; do
    dir="$(dirname "$old")"
    base="$(basename "$old")"
    new="$dir/${base//ExampleMod/$MOD_ID_PASCAL}"
    [[ "$old" != "$new" ]] && mv "$old" "$new"
done

# ── Kotlin support ───────────────────────────────────────────────────────────

if $KOTLIN; then
    echo "Adding Kotlin language support ..."

    KOTLIN_VERSION="2.1.20"
    FABRIC_LANG_KOTLIN_VERSION="1.13.1+kotlin.${KOTLIN_VERSION}"
    KOTLIN_FOR_FORGE_VERSION="5.6.0"

    # Use python3 for reliable multi-line text manipulation (works on macOS + Linux)
    python3 - "$TARGET" "$KOTLIN_VERSION" "$FABRIC_LANG_KOTLIN_VERSION" "$KOTLIN_FOR_FORGE_VERSION" <<'PYEOF'
import sys, os, re

target = sys.argv[1]
kotlin_ver = sys.argv[2]
flk_ver = sys.argv[3]
kff_ver = sys.argv[4]

def read(p):
    with open(os.path.join(target, p)) as f: return f.read()
def write(p, c):
    with open(os.path.join(target, p), 'w') as f: f.write(c)

# 1. Add Kotlin Gradle plugin to buildSrc
c = read("buildSrc/build.gradle.kts")
c = c.replace(
    'implementation("net.fabricmc:fabric-loom:',
    f'implementation("org.jetbrains.kotlin:kotlin-gradle-plugin:{kotlin_ver}")\n    implementation("net.fabricmc:fabric-loom:'
)
write("buildSrc/build.gradle.kts", c)

# 2. Create kotlin-support convention plugin
write("buildSrc/src/main/kotlin/kotlin-support.gradle.kts", """\
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(findProperty("java.version")?.toString()?.toInt() ?: 21)
}
""")

# 3. Apply kotlin-support in module build scripts
for rel in ("common/build.gradle.kts", "fabric/build.gradle.kts", "neoforge/build.gradle.kts"):
    c = read(rel)
    c = c.replace('plugins {\n', 'plugins {\n    id("kotlin-support")\n', 1)
    write(rel, c)

# 4. Add fabric-language-kotlin dependency to fabric
c = read("fabric/build.gradle.kts")
c = c.replace(
    'add("modImplementation", "net.fabricmc:fabric-loader:',
    f'add("modImplementation", "net.fabricmc:fabric-loader:'
)
# Insert after the fabric-loader modImplementation line
c = re.sub(
    r'(add\("modImplementation", "net\.fabricmc:fabric-loader:[^"]*"\))',
    r'\1\n    add("modImplementation", "net.fabricmc:fabric-language-kotlin:' + flk_ver + '")',
    c
)
write("fabric/build.gradle.kts", c)

# 5. Add fabric-language-kotlin to fabric.mod.json depends
c = read("fabric/src/main/resources/fabric.mod.json")
c = c.replace(
    '"fabricloader": ">=0.15.0"',
    f'"fabricloader": ">=0.15.0",\n    "fabric-language-kotlin": ">={flk_ver}"'
)
write("fabric/src/main/resources/fabric.mod.json", c)

# 6. Add KotlinForForge to neoforge
c = read("neoforge/build.gradle.kts")

# Add repository before neoForge block
c = c.replace(
    'neoForge {',
    'repositories {\n    maven("https://thedarkcolour.github.io/KotlinForForge/")\n}\n\nneoForge {'
)

# Add additionalRuntimeClasspathConfiguration after version line
c = c.replace(
    '    version = neoforgeVersion\n',
    '    version = neoforgeVersion\n\n    additionalRuntimeClasspathConfiguration.add(configurations.getByName("implementation"))\n'
)

# Add KotlinForForge dependency at the end
c += '\ndependencies {\n    implementation("thedarkcolour:kotlinforforge-neoforge:' + kff_ver + '")\n}\n'

write("neoforge/build.gradle.kts", c)

# 7. Update neoforge.mods.toml to use kotlinforforge loader
c = read("neoforge/src/main/resources/META-INF/neoforge.mods.toml")
c = c.replace('modLoader="javafml"', 'modLoader="kotlinforforge"')
write("neoforge/src/main/resources/META-INF/neoforge.mods.toml", c)

print("  Python modifications applied.")
PYEOF

    echo "Kotlin support enabled."
fi

# ── Initialise git ───────────────────────────────────────────────────────────

if ! git -C "$TARGET" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Initialising git repository ..."
    git -C "$TARGET" init -b main
    git -C "$TARGET" add .
    git -C "$TARGET" commit -m "Initial project from mc-blueprint template"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Your mod project is ready at: $TARGET"
echo ""
echo "Next steps:"
echo "  1. Open the project in IntelliJ IDEA"
echo "  2. Let Gradle sync complete"
echo "  3. Start coding in common/src/main/java/..."
echo ""
echo "Useful Gradle tasks:"
echo "  ./gradlew build                    Build the active version"
echo "  ./gradlew stageArtifacts           Build all versions and stage JARs"
echo '  ./gradlew "Set active project to neoforge-1.21.11"'
