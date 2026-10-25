---
name: bootstrap-ci-builder
description: GitHub のブランチ・タグごとに、そのコミットに固定したワンライナーのインストーラ（install.sh。curl | sh で実行）を GitHub Actions で生成・頒布し、導入後は常設コマンド（「アプリ名-ctl」）で update・ブランチ/タグの切り替え（--ref）・uninstall できるようにする仕組みを、リポジトリへ整備・更新する。設定ファイル（.env）の生成・反映と、root での導入・一般ユーザー（sudo 不要）での導入の両方に対応する。「install.sh を作りたい」「curl 1行でインストールできるようにしたい」「頒布用のインストーラ」「インストーラのワークフロー」「ブランチやタグを指定して導入・更新したい」「インストーラに update / uninstall を付けたい」といった依頼や、installer/ を持つリポジトリのインストーラを直す・このスキルの新しい版へ追従させるときに使う。
---

# ブートストラップ型インストーラ・CI整備

リポジトリに次の仕組みを整える。

- ブランチ・タグへの push ごとに、GitHub Actions がそのコミットに固定した `install.sh` を作る。タグ（`v*`）は GitHub Release に添付し、ブランチは CI の artifact に保存する。
- 利用者は `curl … | sh -s -- install` の1行で導入する。導入後は `<アプリ名>-ctl` で、導入中のブランチ・タグへの追従（`update`）、別のブランチ・タグへの切り替え（`--ref`）、削除（`uninstall`）を行う。
- 設定は `config.schema` で宣言したキーだけを `.env` に持ち、`--set`・環境変数・手編集の値を決まった優先順位で反映する。

仕組み（取得・コミットの照合・参照の解決・設定・導入メタ情報・常設コマンド）は**コア**として全プロジェクト共通にし、プロジェクトが書くのは**アプリ側**の数ファイルだけにする。アプリを何で動かすか（systemd・コンテナ・単なるコマンドの配置など）は、アプリ側のフックの中身であって、このスキルでは決めない。

```
[install.sh]  curl … | sh -s -- install [--ref 名前] [--set K=V …]   ← 取得してコミットを照合し、main.sh へ委譲
      │                         update / uninstall               ← 導入済みの常設コマンドへ委譲
      ▼
[installer/main.sh]  参照の解決 → 設定の検証・反映 → app_install（app.sh） → 導入メタ情報 → 常設コマンド
      ▼ 導入後は curl 不要
[<アプリ名>-ctl]  update [--ref 名前] [--set K=V …] / refs / status / uninstall [--purge]
```

## ファイル構成

| 区分 | ファイル | 内容 |
|---|---|---|
| コア（編集しない） | `installer/bootstrap.sh.tmpl` | 頒布する `install.sh` のひな形。`@@…@@` は CI が埋める |
| | `installer/build-bootstrap.sh` | ひな形へ REF・COMMIT・REPO_URL と `app.conf` の値を埋め込み、`install.sh` を標準出力へ出す |
| | `installer/main.sh` | 本体。サブコマンド・設定・導入メタ情報・常設コマンド |
| | `.github/workflows/release-installer.yml` | 検査・生成・artifact 保存・Release 添付 |
| アプリ側（プロジェクトが書く） | `installer/app.conf` | `APP_NAME`・`INSTALL_MODE`（`system`/`user`）、任意で `CTL_NAME`・`CTL_SUBCOMMAND`・`DATA_DIR` |
| | `installer/app.sh` | フック `app_install`・`app_uninstall`・`app_purge` |
| | `installer/config.schema` | 設定キーの宣言。設定が無ければ空でよい |
| | `.github/workflows/installer-check.yml` | 頒布の前に通すプロジェクト固有の検査（`workflow_call`） |

コアを編集しないのは、`scripts/sync.sh` で上書きするだけでこのスキルの更新に追従できるようにするためである。コアに不具合や不足があれば、利用先ではなくこのスキルの `assets/core/` を直し、`tests/e2e.sh` を通してから各リポジトリへ配る。

サブコマンド・配置先・設定の優先順位・各ファイルの書式は [references/spec.md](references/spec.md) にある。README を書くときや、利用者からの質問に答えるときに読む。

## 着手前に確認する事項

推測で進めず、次のうち分からないものは実装の前にユーザーへ確認する。

1. **アプリ名**（`APP_NAME`。英小文字・数字・`-`）。取得先 `/opt/<アプリ名>`・設定 `/etc/<アプリ名>/<アプリ名>.env`・常設コマンド `<アプリ名>-ctl` などの名前になる。アプリ自身のコマンド名と常設コマンド名がぶつかるなら `CTL_NAME` を決める。アプリが自前のコマンドを持ち、そのサブコマンド（例 `<アプリ名> self update`）で更新・削除させたいなら `CTL_SUBCOMMAND` を使う（下記「フックの契約」）。
2. **導入方式**（`INSTALL_MODE`）。`system` は root で `/opt`・`/etc`・`/var/lib`・`/usr/local/bin` へ、`user` は sudo なしで `$HOME` 配下へ導入する。
3. **設定キー**（キー名・既定値・必須か・説明）と、そのうち秘匿値（パスワード・トークン）はどれか。アプリが設定をどう読むか（`. "$CONF_FILE"`、systemd の `EnvironmentFile=` など）。
4. **導入物と削除範囲**。取得先（`$DIR`）の外に置くもの（サービス定義・コマンドへのリンク・ユーザーなど）と、`uninstall` で消すもの・`--purge` のときだけ消すものの線引き。
5. **頒布前の検査**。そのプロジェクトのテスト・lint のうち、通らなければ `install.sh` を出すべきでないもの。
6. **依存**。`install.sh` が自分で入れるのは git と ca-certificates だけ（system 方式かつ apt-get がある場合）。アプリの依存は `app_install` で入れる。user 方式では昇格できないので、不足を知らせて止める。

## 作業手順

1. コアとアプリ側のひな形を置く: `sh <このスキル>/scripts/sync.sh <対象リポジトリ>`。コアは上書きされ、アプリ側は無いときだけ置かれる。
2. `installer/app.conf` に確認した値を書く（書式は spec.md）。
3. `installer/config.schema` に設定キーを1行1キーで書く。
4. `installer/app.sh` のフックを書く（下記「フックの契約」）。処理が無いフックは `:` のままにする（空の関数は構文エラーになる）。
5. `.github/workflows/installer-check.yml` のステップに、確認した検査を書く。既存の CI に同じ検査があれば、それを流用する。
6. ローカルで検証する（[references/verification.md](references/verification.md)）。コアの動作はこのスキルの `tests/e2e.sh` で確認済みなので、プロジェクトでは**フックが正しく導入・再適用・削除できるか**を確かめる。
7. README に導入手順を書く（spec.md の「README に書くこと」）。

## フックの契約（`installer/app.sh`）

`main.sh` が `app.sh` を読み込み、同じシェルの中でフックを呼ぶ。フックから使えるもの:

| 名前 | 内容 |
|---|---|
| `$APP` | アプリ名 |
| `$DIR` | 取得先（このリポジトリのチェックアウト） |
| `$CONF_FILE` | 設定ファイル。`. "$CONF_FILE"` で値を読める（その行の前に `# shellcheck source=/dev/null`） |
| `$DATA_DIR` | データディレクトリ（`--purge` で削除される） |
| `$BIN_DIR` | 常設コマンドを置く場所（system: `/usr/local/bin`、user: `$HOME/.local/bin`）。`app_install` の時点で存在する |
| `$INSTALL_MODE` | `system` か `user` |
| `$SUB` | `install` か `update` |
| `log` `warn` `die` | 表示・中止 |

- `app_install`: 設定の反映後、導入メタ情報と常設コマンドの配置より前に、`install`・`update` のたびに呼ばれる。失敗すると（`die` や `set -e` で止まると）導入メタ情報と常設コマンドは更新されず、設定ファイルだけが反映済みで残る。**何度実行しても同じ結果になる**ように書く。`update` では新しい版の `app.sh` で呼ばれるので、配置物は毎回上書きし、サービスなら再読み込み・再起動まで行う。
- `app_uninstall`: `uninstall` の最初に呼ばれる。`$DIR` の外に置いた導入物（サービスの停止と定義の削除、リンクなど）を片付ける。**存在しない物があっても失敗しない**こと。
- `app_purge`: `--purge` のときだけ `app_uninstall` の後に呼ばれる。設定・データ・導入メタ情報はコアが消すので、それ以外（作ったユーザーなど）だけを消す。

`CTL_SUBCOMMAND` を指定したときは、コアは常設コマンドを置かない。代わりに `app_install` が `$BIN_DIR/<CTL_NAME>` を置き、そのコマンドは `<CTL_NAME> <CTL_SUBCOMMAND> <サブコマンド> [引数…]` を受けたら `sh "$DIR/installer/main.sh" <サブコマンド> [引数…]` を実行する。置かれていなければ `install` は失敗する。

フックが長くなるなら、`installer/` の下に別ファイルを置いて `app.sh` から読み込んでよい。

## 書き方の決まり

- `install.sh` とコアは利用者に頒布される。コメントやアプリ固有の説明を入れず、`--help` とエラーメッセージ、`config.schema` の1行説明だけを残す。仕様の説明は spec.md と README に書く。
- 生成物に「このスキルのテンプレートから作った」といった自己言及を残さない。
- 頒布物の名前は `install.sh` で固定する。ブランチ用のタグや Pre-release は作らない（ブランチとタグの名前が衝突し、更新のたびに完全名での指定が要るようになるため）。ブランチは Release の `install.sh` に `--ref <ブランチ名>` を付けて導入する。

## 既存のインストーラがあるリポジトリ

`installer/app.conf` と `installer/app.sh` があれば、`scripts/sync.sh` を実行し、`git diff` でコアの差分を確かめるだけでよい。

それらが無い古い形（フックや `{{APP_NAME}}` の値が `main.sh` に直接書かれている形）なら、先に `main.sh` のフックの中身を `app.sh` へ、アプリ名・導入方式を `app.conf` へ移してから `sync.sh` を実行する。旧 `main.sh` の固有部分は `git diff` で拾える。
