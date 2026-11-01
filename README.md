# betterleaks-ja-pre-commit

[![test](https://github.com/hii-chi/betterleaks-ja-pre-commit/actions/workflows/test.yml/badge.svg)](https://github.com/hii-chi/betterleaks-ja-pre-commit/actions/workflows/test.yml)

コードに紛れ込んだ **日本語で書いたパスワード・メールアドレス・実名入りのパス** を、コミットの手前で止める Git の pre-commit フックです。
[Betterleaks](https://github.com/betterleaks/betterleaks) に日本語のルールを足し、awk の補助チェックを組み合わせています。

GitHub Free の個人アカウントのプライベートリポジトリでは、シークレットスキャンも push protection も使えません。その代わりとして、ローカルのコミット時に止めます。

詳しい背景と設計は記事を参照してください：
[コードに紛れ込んだパスワードとメールアドレスを、コミット前に Betterleaks で止める](https://zenn.dev/hii_chi/articles/betterleaks-pre-commit-japanese-password)

## 何を止めるか

| コードに書いた行 | Betterleaks のデフォルトだけ | このフック |
|---|---|---|
| `const password = "Zq8vR2mXw4Lp9TnK";` | 止まる | 止まる |
| `// パスワードは Zq8vR2mXw4Lp9TnK です。` | 止まらない | **止まる** |
| `// パスワードは自分で決めます。` | 止まらない | 止まらない |
| `const reportTo = "someone@mail.invalid";` | 止まらない | **止まる** |
| `const sshDir = "/home/taro/.ssh";` | 止まらない | **止まる** |

例外として、`@example.com` / `.org` / `.net` のアドレス、`/home/node`、`C:\Users\Public` と `/mnt/c/Users/Public` は止めません。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `.githooks/pre-commit` | フック本体。ステージした変更を Betterleaks と awk で調べる |
| `.betterleaks.toml` | 日本語のパスワードのルール `ja-password` を足した Betterleaks の設定 |
| `scripts/install-betterleaks.sh` | Betterleaks をバージョン固定・SHA256 検証付きで入れる（Linux / macOS） |
| `tests/` | [bats](https://github.com/bats-core/bats-core) によるテスト |
| `.github/workflows/test.yml` | CI（shellcheck、フックとインストーラーの実行権限の確認、Linux x64 / arm64・macOS でのテスト） |

## 自分のリポジトリへの導入手順

1. Betterleaks をインストールする（Homebrew などで入れてもかまいません。動作確認は 1.9.0 で行っています）

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/hii-chi/betterleaks-ja-pre-commit/main/scripts/install-betterleaks.sh
   bash install-betterleaks.sh "$HOME/.local/bin"   # PATH が通った場所を指定
   ```

2. 2 つのファイルを自分のリポジトリのルートにコピーする

   ```sh
   cp -r path/to/betterleaks-ja-pre-commit/.githooks .
   cp path/to/betterleaks-ja-pre-commit/.betterleaks.toml .
   chmod +x .githooks/pre-commit
   ```

3. フックを有効にする（clone ごとに 1 回必要です）

   ```sh
   git config core.hooksPath .githooks
   ```

誤検出で止まったときは、内容を確かめたうえで `git commit --no-verify` で通してください。

## テストを動かす

必要なもの：`git`、`bash`、`betterleaks`、`bats`

```sh
# bats のインストール例
#   Debian/Ubuntu: sudo apt-get install bats
#   macOS:         brew install bats-core bash   # bash も入れる（下の注意を参照）
#   npm:           npm install -g bats

bats tests
```

> **注意：macOS では、Homebrew などで新しい bash を入れてください。**
> macOS に最初から入っている bash（`/bin/bash`、3.2）では、bats が日本語のテスト名を扱えません。`bats: unknown test name ...` と出て、テストが 1 件も動きません。
> `brew install bash` のあと、`bash --version` が 5 以上になっていれば大丈夫です（3.2 のままなら、Homebrew の `bin` が `PATH` の先頭に来ているか確かめてください）。
>
> フック自体は bash 3.2 でも動きます。macOS 標準の bash でフックを動かしてテストしたいときは、`HOOK_SHELL` でフックを動かすシェルを指定できます（CI の macOS でもこの形で動かしています）。
>
> ```sh
> HOOK_SHELL=/bin/bash bats tests
> ```

テストは、一時ディレクトリに使い捨ての Git リポジトリを作り、このリポジトリのフックと設定を入れて **実際に `git commit` を実行** して、止まる／通るを確かめます。利用者の `~/.gitconfig` や `BETTERLEAKS_CONFIG` などの環境変数の影響は受けません。

### テストの一覧

テスト名は `tests/pre-commit.bats` の `@test` と同じです。一覧とテストがずれていないかは、CI の `lint` ジョブ（`scripts/check-readme-tests.sh`）で確かめています。テストを足したり名前を変えたりしたときは、この一覧も直してください。

<!-- tests:start -->
#### 基本

| テスト名 | 確かめていること |
|---|---|
| 問題のないファイルはコミットできる | 誤検出せずにコミットが通る |
| 英語の password = "..." はデフォルトのルールで止まる | Betterleaks のデフォルトのルール（`generic-password`）が効いている |
| 見つかった値はターミナルに出さない（--redact） | 出力が `REDACTED` になり、値そのものは出ない |

#### 日本語のパスワードのルール（ja-password）

既知の制限（暗証番号の誤検出、「パスワードを xxx に」の見逃し）も、そのまま期待値にしています。ルールを変えて挙動が変わると、テストが落ちて気づけます。

| テスト名 | 確かめていること |
|---|---|
| ja-password: 日本語で書いたパスワードは止まる（暗証番号の誤検出も含む） | 「パスワードは xxx」「パスワード: xxx」「パスフレーズ：xxx」で止まる。「暗証番号が」の後に 4 桁の数字が続く文（誤検出）でも止まる |
| ja-password: 止まったときはルール名 ja-password が出る | どのルールで止まったかが出力でわかる |
| ja-password: 説明文や「パスワードを xxx に」は止まらない（既知の制限を含む） | 「自分で決めます」「8 文字以上」「`<パスワード>`」などの説明文では止まらない |

#### awk のチェック（メールアドレス・実名入りのパス）

| テスト名 | 確かめていること |
|---|---|
| awk: メールアドレスと実名入りのパスは止まる | メールアドレス、`/home/<名前>`、`C:\Users\<名前>`、`/mnt/c/Users/<名前>` で止まる。例外と同じ行にあっても止まる |
| awk: 例外（example.com/org、/home/node、Public）は止まらない | 例外だけの行では止まらない |
| Betterleaks と awk の結果が 1 回のコミットでまとめて出る | 両方の結果が出て、行番号が正しく、例外の行は出ない |
| awk: 日本語のファイル名がそのまま表示される（core.quotepath=false） | `\351\200...` のようなエスケープにならない |
| awk: 既存の行は検出し直さず、追加した行だけを見る | すでにコミット済みの行で止まらない |

#### 名前の変更とコピー

| テスト名 | 確かめていること |
|---|---|
| 名前を変えたファイル（R）に足した行も止まる | `git mv` したファイルに足した行が awk のチェックを素通りしない |
| diff.renames=copies でコピー（C）扱いのファイルに足した行も止まる | `--diff-filter` に `C` が入っている |

#### 設定ファイルと実行環境

| テスト名 | 確かめていること |
|---|---|
| betterleaks が PATH にないとコミットを止める | Betterleaks がないまま素通りしない |
| .betterleaks.toml がないとコミットを止める | `--config` で渡しているので、設定がなければエラーで止まる |
| 環境変数 BETTERLEAKS_CONFIG に別の設定があっても ja-password が効く | `--config` が環境変数より優先される |
| サブディレクトリからコミットしても ja-password が効く | コミットする場所によらず設定が読まれる |

#### Betterleaks の挙動の見張り

| テスト名 | 確かめていること |
|---|---|
| Betterleaks の既知の挙動: 日本語の keywords を付けると ja-password が動かない | v1.9.0 の挙動。Betterleaks を上げてこのテストが落ちたら、Betterleaks で直った可能性があるので、`keywords` を付けられるか検討する |
<!-- tests:end -->

### Betterleaks のバージョンを上げるとき

`scripts/install-betterleaks.sh` の既定値と `.github/workflows/test.yml` の `matrix.betterleaks` を書き換えて CI を通します。新旧を並べて試すなら、matrix に両方のバージョンを書けます。

## このリポジトリ自体を開発するとき

`tests/fixtures/` と この README には、わざと検出させるための文字列（偽のパスワード・メールアドレス・パス）を置いています。このリポジトリで `core.hooksPath` を有効にしている場合、それらを変更したコミットはフックで止まるので、内容を確かめたうえで `--no-verify` で通してください。テストコード（`.bats`）には検出される文字列を直接書かず、fixture から読むようにしています。

## 既知の制限

- `git commit --no-verify` で飛ばせます。
- ステージした変更だけを調べるので、コミット済みの履歴は調べません（履歴を調べるなら `betterleaks git .` を別途実行してください）。
- 日本語のルールは「パスワード・パスフレーズ・暗証番号」の後に「は・が・:・：・=」が続く書き方だけを拾います。「パスワードを xxx にします」は拾いません。
- 「暗証番号が 1234 だと弱いです」のように、本物でなくても止まることがあります。
- 文字列リテラルの中でバックスラッシュをエスケープした Windows のパス（例：`"C:\\Users\\taro"`）は、awk のチェックを通ってしまいます。

## ライセンス

[MIT](LICENSE)
