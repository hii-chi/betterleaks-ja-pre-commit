# テスト用の共通処理。
# 各テストごとに一時ディレクトリに使い捨ての Git リポジトリを作り、
# このリポジトリの .githooks/pre-commit と .betterleaks.toml を入れて、実際に git commit する。
# $status と $output は bats の run が設定する
# shellcheck disable=SC2154

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
  # 利用者の ~/.gitconfig や環境変数がテスト結果に影響しないようにする
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
  unset BETTERLEAKS_CONFIG GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML BETTERLEAKS_CONFIG_TOML
  git config --global user.name "test"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main

  WORK="${BATS_TEST_TMPDIR}/repo"
  git init -q "$WORK"
  cd "$WORK" || return 1
  mkdir -p .githooks src
  cp "${REPO_ROOT}/.githooks/pre-commit" .githooks/pre-commit
  # HOOK_SHELL を指定すると、フックをそのシェルで動かす（1 行目の #! を書き換える）
  # 例: macOS の CI で、bats は Homebrew の bash 5、フックは標準の /bin/bash（3.2）で動かす
  if [ -n "${HOOK_SHELL:-}" ]; then
    sed -i.bak "1s|.*|#!${HOOK_SHELL}|" .githooks/pre-commit
    rm -f .githooks/pre-commit.bak
  fi
  chmod +x .githooks/pre-commit
  cp "${REPO_ROOT}/.betterleaks.toml" .betterleaks.toml
  git config core.hooksPath .githooks
  git add -A
  git commit -q --no-verify -m "init"
}

# fixture を src/<名前> としてステージしてコミットする。結果は $status / $output に入る
# 使い方: commit_fixture <fixture> [置き先]
commit_fixture() {
  local src="$1" dest="${2:-src/$1}"
  mkdir -p "$(dirname "$dest")"
  cp "${FIXTURES}/${src}" "$dest"
  git add -- "$dest"
  run git commit -m "test: ${dest}"
}

# 1 行だけのファイルをコミットする
commit_line() {
  local line="$1" dest="${2:-src/case.js}"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$line" > "$dest"
  git add -- "$dest"
  run git commit -m "test: one line"
}

# 直前のコミットの試みでコミットが作られていないこと
assert_blocked() {
  if [ "$status" -eq 0 ]; then
    echo "コミットが通ってしまいました。出力:" >&2
    echo "$output" >&2
    return 1
  fi
  [[ "$output" == *"コミットを止めました"* ]] || {
    echo "フックのメッセージがありません。出力:" >&2
    echo "$output" >&2
    return 1
  }
}

assert_committed() {
  if [ "$status" -ne 0 ]; then
    echo "コミットが止まりました。出力:" >&2
    echo "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  [[ "$output" == *"$1"* ]] || {
    echo "出力に「$1」がありません。出力:" >&2
    echo "$output" >&2
    return 1
  }
}

assert_output_not_contains() {
  [[ "$output" != *"$1"* ]] || {
    echo "出力に「$1」が含まれています。出力:" >&2
    echo "$output" >&2
    return 1
  }
}

# fixture の各行を 1 行ずつ別のコミットとして試し、期待どおりでなかった行を集める
# 使い方: each_line_should <blocked|committed> <fixture>
each_line_should() {
  local expect="$1" fixture="$2" line n=0 failures=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -z "$line" ] && continue
    commit_line "$line" "src/case_${n}.js"
    if [ "$expect" = blocked ] && [ "$status" -eq 0 ]; then
      failures+="  ${fixture}:${n}: 止まるはずが通った: ${line}"$'\n'
    elif [ "$expect" = committed ] && [ "$status" -ne 0 ]; then
      failures+="  ${fixture}:${n}: 通るはずが止まった: ${line}"$'\n'"${output}"$'\n'
    fi
    # 止まった場合はステージを戻して次のケースへ
    [ "$status" -ne 0 ] && git reset -q
  done < "${FIXTURES}/${fixture}"
  if [ -n "$failures" ]; then
    printf '%s' "$failures" >&2
    return 1
  fi
}
