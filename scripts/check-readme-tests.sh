#!/usr/bin/env bash
# README.md のテスト一覧と tests/*.bats の @test の名前が一致しているかを確かめる。
# README の <!-- tests:start --> と <!-- tests:end --> の間にある表の 1 列目を、テスト名として読む。
# （テスト名に | は使わない。表の区切りと区別できなくなるため）
#
# 使い方: bash scripts/check-readme-tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export LC_ALL=C

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# bats の @test "名前" { から名前を取り出す。\" は " に戻す
sed -n 's/^@test "\(.*\)" {[[:space:]]*$/\1/p' tests/*.bats | sed 's/\\"/"/g' > "$tmp/bats"

if ! grep -qxF '<!-- tests:start -->' README.md || ! grep -qxF '<!-- tests:end -->' README.md; then
  echo "check-readme-tests: README.md に <!-- tests:start --> と <!-- tests:end --> の行がありません。" >&2
  exit 1
fi

# 印の間の表の行の 1 列目。見出し行（テスト名）と区切り行（|---|）は除く
awk '
  $0 == "<!-- tests:start -->" { on = 1; next }
  $0 == "<!-- tests:end -->" { on = 0 }
  on && /^\|/ && $0 !~ /^\|[-:| ]+$/ {
    split($0, c, "|")
    name = c[2]
    gsub(/^[ \t]+|[ \t]+$/, "", name)
    if (name != "テスト名") print name
  }
' README.md > "$tmp/readme"

failed=0

for side in bats readme; do
  dups="$(sort "$tmp/$side" | uniq -d)"
  if [ -n "$dups" ]; then
    echo "check-readme-tests: ${side} に同じテスト名が重複しています:" >&2
    printf '  %s\n' "$dups" >&2
    failed=1
  fi
done

sort -u "$tmp/bats" > "$tmp/bats.sorted"
sort -u "$tmp/readme" > "$tmp/readme.sorted"

missing="$(comm -23 "$tmp/bats.sorted" "$tmp/readme.sorted")"
extra="$(comm -13 "$tmp/bats.sorted" "$tmp/readme.sorted")"

if [ -n "$missing" ]; then
  echo "check-readme-tests: README.md の一覧にないテストがあります（tests/*.bats にはある）:" >&2
  while IFS= read -r l; do echo "  $l" >&2; done <<< "$missing"
  failed=1
fi
if [ -n "$extra" ]; then
  echo "check-readme-tests: README.md の一覧にあるのに tests/*.bats にないテストがあります（名前の違いを含む）:" >&2
  while IFS= read -r l; do echo "  $l" >&2; done <<< "$extra"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "check-readme-tests: README.md の一覧と tests/*.bats のテスト名は一致しています（$(wc -l < "$tmp/bats.sorted" | tr -d ' ') 件）。"
