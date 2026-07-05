#!/usr/bin/env bash
# Build scripts/tl-http-agent.jar: a fat JAR with Byte Buddy bundled in. No sudo,
# no Maven, no Gradle. Just javac + jar + a pinned download.
#
# The output JAR is a build artifact, gitignored, never committed. Only this script
# & TLHttpAgent.java live in the repo. Nothing is written outside this tree.
#
# Third-party: the fat JAR bundles Byte Buddy 1.14.18 (Apache-2.0). Step 6 adds a
# NOTICE into the JAR so the attribution rides along if the artifact is ever shared.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_VER="1.14.18"
BB_JAR="${SCRIPT_DIR}/.deps/byte-buddy-${BB_VER}.jar"
BB_URL="https://search.maven.org/remotecontent?filepath=net/bytebuddy/byte-buddy/${BB_VER}/byte-buddy-${BB_VER}.jar"
# SHA256 verified against Maven Central's published SHA1 (0081e9b9...20944626e6757b5950676af901c2485).
BB_SHA256="52117af1696a53aa77c131353074ada25ccbdf2df511f2af33fad6704fa95104"
OUT_JAR="${SCRIPT_DIR}/tl-http-agent.jar"
SRC="${SCRIPT_DIR}/TLHttpAgent.java"
BUILD="${SCRIPT_DIR}/.build"

# 1. javac is required (default-jdk). The runtime JRE alone can't compile.
command -v javac >/dev/null 2>&1 || { echo "javac not found. Install default-jdk." >&2; exit 1; }

# 2. Download Byte Buddy once, pinned by SHA256. A mismatch aborts & deletes it.
if [ ! -f "$BB_JAR" ]; then
    mkdir -p "$(dirname "$BB_JAR")"
    wget -q -O "$BB_JAR" "$BB_URL" || curl -fsSL -o "$BB_JAR" "$BB_URL"
    actual="$(sha256sum "$BB_JAR" | cut -d' ' -f1)"
    if [ "$actual" != "$BB_SHA256" ]; then
        rm -f "$BB_JAR"
        echo "SHA256 mismatch for Byte Buddy (${BB_VER}). Aborting." >&2
        echo "  expected $BB_SHA256" >&2
        echo "  got      $actual" >&2
        exit 1
    fi
    echo "Byte Buddy ${BB_VER} downloaded and verified."
fi

# 3. Skip the build if the JAR is already newer than the source.
if [ -f "$OUT_JAR" ] && [ "$OUT_JAR" -nt "$SRC" ]; then
    echo "tl-http-agent.jar is up to date."
    exit 0
fi

# 4. Compile against Byte Buddy only (the agent reads HttpClient5 via reflection).
rm -rf "$BUILD" && mkdir -p "$BUILD/classes"
javac -cp "$BB_JAR" -source 11 -target 11 -d "$BUILD/classes" "$SRC"

# 5. Explode Byte Buddy into the classes dir (this is what makes it a fat JAR).
#    Drop the source manifest & any signatures; ours replaces them below.
cd "$BUILD/classes"
jar xf "$BB_JAR"
rm -f META-INF/MANIFEST.MF META-INF/*.SF META-INF/*.RSA META-INF/*.DSA

# 6. Third-party attribution. Byte Buddy ships its own license inside its JAR, which
#    the jar xf above already carried over; this NOTICE makes the Apache-2.0 credit
#    explicit & survives even if upstream ever drops its copy.
mkdir -p META-INF
cat > META-INF/NOTICE-bytebuddy.txt <<'EOF'
This artifact bundles Byte Buddy 1.14.18 (net.bytebuddy:byte-buddy),
licensed under the Apache License, Version 2.0.
  https://github.com/raphw/byte-buddy
  https://www.apache.org/licenses/LICENSE-2.0
EOF

# 7. Our manifest.
cd "$SCRIPT_DIR"
cat > "$BUILD/MANIFEST.MF" <<'EOF'
Premain-Class: com.github.tlsandbox.agent.TLHttpAgent
Can-Redefine-Classes: false
Can-Retransform-Classes: true
X-Bundled-Dependency: Byte Buddy 1.14.18 (Apache-2.0)

EOF

# 8. Package the fat JAR.
jar cfm "$OUT_JAR" "$BUILD/MANIFEST.MF" -C "$BUILD/classes" .
rm -rf "$BUILD"

echo "Built: $(basename "$OUT_JAR") ($(du -sh "$OUT_JAR" | cut -f1))"
