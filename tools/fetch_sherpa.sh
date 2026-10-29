#!/usr/bin/env bash
# v12: fetches the sherpa-onnx native libraries (arm64) and its Kotlin API into the app, from ONE release, so they always match.
# Run once before building in Android Studio (Git Bash / WSL / Linux / macOS). The GitHub Actions workflow runs it for you.
#   SHERPA_VERSION=1.12.15 bash tools/fetch_sherpa.sh     pin a version
#   bash tools/fetch_sherpa.sh                            use the newest release
set -euo pipefail
cd "$(dirname "$0")/.."

VER="${SHERPA_VERSION:-}"
if [ -z "$VER" ]; then
  VER="$(curl -fsSL https://api.github.com/repos/k2fsa/sherpa-onnx/releases/latest 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/' || true)"
fi
VER="${VER:-1.12.15}"   # last resort if the GitHub API can't be reached; set SHERPA_VERSION yourself if this one is gone
echo "sherpa-onnx version: $VER"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BASE="https://github.com/k2fsa/sherpa-onnx/releases/download/v$VER"

echo "== native libraries =="
curl -fL --retry 3 -o "$TMP/android.tar.bz2" "$BASE/sherpa-onnx-v$VER-android.tar.bz2" \
  || { echo "ERROR: could not download $BASE/sherpa-onnx-v$VER-android.tar.bz2 (check the version on github.com/k2fsa/sherpa-onnx/releases)"; exit 1; }
mkdir -p "$TMP/android"; tar -xjf "$TMP/android.tar.bz2" -C "$TMP/android"
DEST="app/src/main/jniLibs/arm64-v8a"; rm -rf app/src/main/jniLibs; mkdir -p "$DEST"
find "$TMP/android" -path '*arm64-v8a*' -name '*.so' -exec cp {} "$DEST/" \;
ls "$DEST" | grep -q "sherpa-onnx-jni" || { echo "ERROR: libsherpa-onnx-jni.so not found in the release archive"; exit 1; }
echo "$VER" > app/src/main/jniLibs/SHERPA_VERSION
ls -la "$DEST"

echo "== Kotlin API (same tag) =="
curl -fL --retry 3 -o "$TMP/src.tar.gz" "https://github.com/k2fsa/sherpa-onnx/archive/refs/tags/v$VER.tar.gz"
mkdir -p "$TMP/src"; tar -xzf "$TMP/src.tar.gz" -C "$TMP/src" --wildcards '*/sherpa-onnx/kotlin-api/*.kt'
KT="app/src/main/java/com/k2fsa/sherpa/onnx"; rm -rf "$KT"; mkdir -p "$KT"
cp "$TMP"/src/*/sherpa-onnx/kotlin-api/*.kt "$KT/"
for need in OnlineRecognizer OnlineStream FeatureConfig Vad; do
  [ -f "$KT/$need.kt" ] || { echo "ERROR: $need.kt missing from the Kotlin API of v$VER"; exit 1; }
done
ls "$KT"
echo "done. Build now."
