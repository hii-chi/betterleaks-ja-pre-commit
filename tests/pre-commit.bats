#!/usr/bin/env bats
# .githooks/pre-commit の動作テスト。
# 実際に一時リポジトリで git commit を実行し、止まる／通るを確かめる。
# 秘密っぽい文字列は tests/fixtures/ にだけ置き、このファイルには書かない。

load test_helper

# ---------------------------------------------------------------
# 基本
# ---------------------------------------------------------------

@test "問題のないファイルはコミットできる" {
  commit_fixture clean.js
  assert_committed
  assert_output_contains "no leaks found"
}

@test "英語の password = \"...\" はデフォルトのルールで止まる" {
  commit_fixture en_password.js
  assert_blocked
  assert_output_contains "generic-password"
}

@test "見つかった値はターミナルに出さない（--redact）" {
  commit_fixture ja_password_line.js
  assert_blocked
  assert_output_contains "REDACTED"
  assert_output_not_contains "$(grep -o 'Zq8v[A-Za-z0-9]*' "${FIXTURES}/ja_password_line.js")"
}

# ---------------------------------------------------------------
# 日本語のパスワードのルール（ja-password）
# ---------------------------------------------------------------

@test "ja-password: 日本語で書いたパスワードは止まる（暗証番号の誤検出も含む）" {
  each_line_should blocked ja_blocked.txt
}

@test "ja-password: 止まったときはルール名 ja-password が出る" {
  commit_fixture ja_password_line.js
  assert_blocked
  assert_output_contains "ja-password"
}

@test "ja-password: 説明文や「パスワードを xxx に」は止まらない（既知の制限を含む）" {
  each_line_should committed ja_allowed.txt
}

# ---------------------------------------------------------------
# awk の補助チェック（メールアドレス・実名入りのパス）
# ---------------------------------------------------------------

@test "awk: メールアドレスと実名入りのパスは止まる" {
  each_line_should blocked aux_blocked.txt
}

@test "awk: 例外（example.com/org、/home/node、Public）は止まらない" {
  each_line_should committed aux_allowed.txt
}

@test "Betterleaks と awk の結果が 1 回のコミットでまとめて出る" {
  commit_fixture sample.js
  assert_blocked
  assert_output_contains "ja-password"
  assert_output_contains "src/sample.js:4:"
  assert_output_contains "src/sample.js:7:"
  # 例外の行（5 行目と 8 行目）は出ない
  assert_output_not_contains "src/sample.js:5:"
  assert_output_not_contains "src/sample.js:8:"
}

@test "awk: 日本語のファイル名がそのまま表示される（core.quotepath=false）" {
  commit_fixture email_line.js "src/連絡先.js"
  assert_blocked
  assert_output_contains "src/連絡先.js:1:"
}

@test "awk: 既存の行は検出し直さず、追加した行だけを見る" {
  # 既存行として先に入れておく
  cp "${FIXTURES}/email_line.js" src/a.js
  git add src/a.js
  git commit -q --no-verify -m "existing"
  echo "// 追記" >> src/a.js
  git add src/a.js
  run git commit -m "append"
  assert_committed
}

# ---------------------------------------------------------------
# 名前の変更とコピー
# ---------------------------------------------------------------

@test "名前を変えたファイル（R）に足した行も止まる" {
  seq 1 20 | sed 's/^/const line = /' > src/old.js
  git add src/old.js
  git commit -q --no-verify -m "old"
  git mv src/old.js src/new.js
  cat "${FIXTURES}/email_line.js" >> src/new.js
  git add src/new.js
  [[ "$(git diff --cached --name-status)" == R* ]]

  run git commit -m "rename"
  assert_blocked
  assert_output_contains "src/new.js:21:"
}

@test "diff.renames=copies でコピー（C）扱いのファイルに足した行も止まる" {
  git config diff.renames copies
  seq 1 20 | sed 's/^/const line = /' > src/old.js
  git add src/old.js
  git commit -q --no-verify -m "old"
  cp src/old.js src/copy.js
  cat "${FIXTURES}/email_line.js" >> src/copy.js
  echo "const added = 1;" >> src/old.js
  git add src/old.js src/copy.js
  [[ "$(git diff --cached --name-status)" == *C*src/copy.js* ]]

  run git commit -m "copy"
  assert_blocked
  assert_output_contains "src/copy.js:21:"
}

# ---------------------------------------------------------------
# 設定ファイルと実行環境
# ---------------------------------------------------------------

@test "betterleaks が PATH にないとコミットを止める" {
  # git と awk などは残し、betterleaks だけを PATH から外す
  local bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin"
  for cmd in git awk bash env dirname cat sed; do
    ln -s "$(command -v "$cmd")" "$bin/$cmd"
  done
  cp "${FIXTURES}/clean.js" src/clean.js
  git add src/clean.js
  PATH="$bin" run git commit -m "no betterleaks"
  [ "$status" -ne 0 ]
  assert_output_contains "betterleaks が見つかりません"
}

@test ".betterleaks.toml がないとコミットを止める" {
  git rm -q --cached .betterleaks.toml
  rm .betterleaks.toml
  git commit -q --no-verify -m "remove config"
  commit_fixture clean.js
  [ "$status" -ne 0 ]
}

@test "環境変数 BETTERLEAKS_CONFIG に別の設定があっても ja-password が効く" {
  export BETTERLEAKS_CONFIG="${FIXTURES}/default_only.toml"
  commit_fixture ja_password_line.js
  assert_blocked
  assert_output_contains "ja-password"
}

@test "サブディレクトリからコミットしても ja-password が効く" {
  cp "${FIXTURES}/ja_password_line.js" src/pw.js
  git add src/pw.js
  cd src
  run git commit -m "from subdir"
  assert_blocked
  assert_output_contains "ja-password"
}

# ---------------------------------------------------------------
# Betterleaks の挙動の見張り
# ---------------------------------------------------------------

@test "Betterleaks の既知の挙動: 日本語の keywords を付けると ja-password が動かない" {
  # Betterleaks を上げたときにこのテストが落ちたら、Betterleaks で直った可能性がある。
  # そのときは .betterleaks.toml に keywords を付けられるか検討する。
  cp "${FIXTURES}/keywords.toml" .betterleaks.toml
  git add .betterleaks.toml
  git commit -q --no-verify -m "keywords config"
  commit_fixture ja_password_line.js
  assert_output_not_contains "ja-password"
}
