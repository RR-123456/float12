#!/usr/bin/env bash
# Fetches sherpa-onnx native libs (arm64) + Kotlin API from ONE release (names read from the GitHub API, not guessed).
#   SHERPA_VERSION=x.y.z bash tools/fetch_sherpa.sh   pin a version
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
API="https://api.github.com/repos/k2fsa/sherpa-onnx/releases"
if [ -n "${SHERPA_VERSION:-}" ]; then REL="$API/tags/v${SHERPA_VERSION#v}"; else REL="$API/latest"; fi

AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi

echo "== asking GitHub: $REL =="
curl -fsSL "${AUTH[@]}" -H "Accept: application/vnd.github+json" "$REL" -o "$TMP/rel.json" \
  || { echo "ERROR: GitHub API call failed (rate limit or wrong version)"; exit 1; }

TAG="$(grep -m1 '"tag_name"' "$TMP/rel.json" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
echo "release tag: $TAG"

ASSET="$(grep -o '"browser_download_url": *"[^"]*"' "$TMP/rel.json" \
  | sed -E 's/.*"(https[^"]*)"/\1/' \
  | grep -E '/sherpa-onnx-v[0-9.]+-android\.tar\.bz2$' | head -1 || true)"
if [ -z "$ASSET" ]; then
  echo "ERROR: no plain Android archive in release $TAG. Files in this release:"
  grep -o '"browser_download_url": *"[^"]*"' "$TMP/rel.json" | sed -E 's/.*\/([^\/"]+)"/  \1/'
  exit 1
fi
echo "native libs: $ASSET"
curl -fL --retry 3 -o "$TMP/android.tar.bz2" "$ASSET"
mkdir -p "$TMP/android"; tar -xjf "$TMP/android.tar.bz2" -C "$TMP/android"
DEST="app/src/main/jniLibs/arm64-v8a"; rm -rf app/src/main/jniLibs; mkdir -p "$DEST"
find "$TMP/android" -path '*arm64-v8a*' -name '*.so' -exec cp {} "$DEST/" \;
ls "$DEST" | grep -q "sherpa-onnx-jni" || { echo "ERROR: libsherpa-onnx-jni.so not in the archive. Found:"; find "$TMP/android" -name '*.so' | head -20; exit 1; }
echo "$TAG" > app/src/main/jniLibs/SHERPA_VERSION
ls -la "$DEST"

echo "== Kotlin API ($TAG) =="
curl -fL --retry 3 -o "$TMP/src.tar.gz" "https://github.com/k2fsa/sherpa-onnx/archive/refs/tags/$TAG.tar.gz"
mkdir -p "$TMP/src"; tar -xzf "$TMP/src.tar.gz" -C "$TMP/src" --wildcards '*/sherpa-onnx/kotlin-api/*.kt'
KT="app/src/main/java/com/k2fsa/sherpa/onnx"; rm -rf "$KT"; mkdir -p "$KT"
cp "$TMP"/src/*/sherpa-onnx/kotlin-api/*.kt "$KT/"
for need in OnlineRecognizer OnlineStream FeatureConfig Vad; do
  [ -f "$KT/$need.kt" ] || { echo "ERROR: $need.kt missing from the Kotlin API of $TAG. Found:"; ls "$KT"; exit 1; }
done
ls "$KT"
echo "done."
