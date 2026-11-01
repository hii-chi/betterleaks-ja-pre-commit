#!/usr/bin/env bash
# Betterleaks をバージョン固定でインストールする。
# リリースの checksums.txt で SHA256 を検証してから展開する。
# devcontainer の Dockerfile と GitHub Actions の両方から使う。
#
# 使い方: scripts/install-betterleaks.sh [インストール先ディレクトリ]
#   BETTERLEAKS_VERSION でバージョンを変えられる（既定: 1.9.0）
set -euo pipefail

VERSION="${BETTERLEAKS_VERSION:-1.9.0}"
DEST="${1:-/usr/local/bin}"

case "$(uname -s)" in
  Linux) OS=linux ;;
  Darwin) OS=darwin ;;
  *) echo "install-betterleaks: 未対応の OS です: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "install-betterleaks: 未対応の CPU です: $(uname -m)" >&2; exit 1 ;;
esac

ASSET="betterleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
BASE="https://github.com/betterleaks/betterleaks/releases/download/v${VERSION}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

curl -fsSLO "${BASE}/${ASSET}"
curl -fsSLO "${BASE}/checksums.txt"

# macOS には sha256sum がないことがあるので shasum で代用する
if command -v sha256sum >/dev/null 2>&1; then
  grep " ${ASSET}$" checksums.txt | sha256sum -c -
else
  grep " ${ASSET}$" checksums.txt | shasum -a 256 -c -
fi

mkdir -p "$DEST"
tar -xzf "$ASSET" -C "$DEST" --no-same-owner betterleaks
"$DEST/betterleaks" version
