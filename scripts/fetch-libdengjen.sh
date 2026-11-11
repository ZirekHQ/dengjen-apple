#!/usr/bin/env bash
# Usage: scripts/fetch-libdengjen.sh
# Puts Libdengjen.xcframework into Frameworks/, as pinned by libdengjen.lock.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/libdengjen.lock"
out="$root/Frameworks"
name="Libdengjen.xcframework"

value() { sed -n "s/^$1=//p" "$lock" | tail -n1; }
source_kind="$(value source)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rm -rf "${out:?}/$name"
mkdir -p "$out"

case "$source_kind" in
  release)
    version="$(value version)"
    sha256="$(value sha256)"
    [ -n "$version" ] && [ -n "$sha256" ] || { echo "libdengjen.lock needs version and sha256" >&2; exit 1; }
    zip="$work/libdengjen.zip"
    curl -fsSL --retry 3 -o "$zip" \
      "https://github.com/ZirekHQ/dengjen/releases/download/v$version/dengjen-apple-$version.xcframework.zip"
    echo "$sha256  $zip" | shasum -a 256 -c -
    ditto -x -k "$zip" "$out"
    ;;
  git)
    ref="$(value ref)"
    [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || { echo "libdengjen.lock ref must be a full commit SHA" >&2; exit 1; }
    src="$work/dengjen"
    git init -q "$src"
    git -C "$src" fetch -q --depth 1 https://github.com/ZirekHQ/dengjen.git "$ref"
    git -C "$src" checkout -q FETCH_HEAD
    if command -v brew >/dev/null; then
      export LIBCLANG_PATH="${LIBCLANG_PATH:-$(brew --prefix llvm)/lib}"
    fi
    (cd "$src" && rustup target add aarch64-apple-darwin >/dev/null)
    (cd "$src" && APPLE_TARGETS=aarch64-apple-darwin APPLE_FEATURES=coreml,voices \
      APPLE_OUT_DIR="$work/apple" CARGO_TARGET_DIR="${LIBDENGJEN_TARGET_DIR:-$work/target}" \
      bindings/apple/scripts/build-xcframework.sh release)
    ditto "$work/apple/$name" "$out/$name"
    ;;
  *)
    echo "libdengjen.lock: unknown source '$source_kind'" >&2
    exit 1
    ;;
esac
echo "$out/$name"
