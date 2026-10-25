# インストーラの仕様

利用者から見た動作と、アプリ側ファイルの書式。README を書くとき・質問に答えるとき・不具合を調べるときに参照する。

## 目次

- サブコマンドとオプション
- ブランチ・タグの指定（`--ref`）
- 配置先
- 設定値の決まり方
- `app.conf` の書式
- `config.schema` の書式
- CI の動作
- README に書くこと

## サブコマンドとオプション

| 実行 | 内容 |
|---|---|
| `install [--ref 名前] [--set KEY=VALUE …]` | 導入する。再実行しても同じ結果になる。`--ref` なしは `install.sh` に埋め込まれた REF・コミット、`--ref` ありはそのブランチ・タグの先頭 |
| `update [--ref 名前] [--set KEY=VALUE …]` | 導入中の REF の最新を取得し、新しい版の `main.sh` で再適用する。`--ref` で切り替えると、以後は切り替え先に追従する。`install.sh` 経由でも `<アプリ名>-ctl` 経由でも同じ（`install.sh` は導入済みの常設コマンドへ委譲し、埋め込みコミットへは戻さない） |
| `refs` | 取得元のブランチ・タグを `種別<TAB>名前` で表示する（常設コマンドのみ） |
| `status` | 導入先・導入方式・参照・コミット・取得元・更新日時・設定ファイルを表示する（常設コマンドのみ） |
| `uninstall` | `app_uninstall` の対象・常設コマンド・取得先を削除する。設定・データ・導入メタ情報は残す（再導入でそのまま使われる） |
| `uninstall --purge` | 上記に加え、設定・データ・導入メタ情報・`app_purge` の対象も削除する |

## ブランチ・タグの指定（`--ref`）

- 名前は短縮形でよい（`--ref main`・`--ref v1.2.0`・`--ref feat/x`）。`git ls-remote` で取得元を調べて解決する。
  - ブランチだけ・タグだけにある → その完全名にする。
  - 両方にある → エラー。`refs/heads/<名前>` か `refs/tags/<名前>` での指定を促す。
  - どちらにも無い → エラー。導入先・導入メタ情報は変えない（解決は取得より前に行う）。
- 導入メタ情報の REF は完全名（`refs/heads/main` など）で保存する。`update` はこれを取得し直すので、ブランチは最新へ追従し、タグは指すコミットに留まる。
- CI は `build-bootstrap.sh` に `github.ref`（完全名）を渡す。`github.ref_name` ではブランチとタグを区別できない。

## 配置先

| 種別 | system（root） | user（sudo 不要） | 削除されるとき |
|---|---|---|---|
| 取得先（git の作業ツリー） | `/opt/<アプリ名>` | `$HOME/.local/share/<アプリ名>` | `uninstall` |
| 設定 | `/etc/<アプリ名>/<アプリ名>.env` | `$HOME/.config/<アプリ名>/<アプリ名>.env` | `--purge` |
| データ（`DATA_DIR`） | `/var/lib/<アプリ名>` | `$HOME/.local/state/<アプリ名>` | `--purge` |
| 導入メタ情報 | `/var/lib/<アプリ名>-installer/state` | `$HOME/.local/state/<アプリ名>-installer/state` | `--purge` |
| 常設コマンド | `/usr/local/bin/<CTL_NAME>` | `$HOME/.local/bin/<CTL_NAME>` | `uninstall` |

- 取得先は、アプリ名を大文字にして `-` を `_` にし、`_DIR` を付けた環境変数で変えられる（例: `my-app` → `MY_APP_DIR`）。`install` のときだけ見る。
- 設定ファイルは `KEY='VALUE'` 形式で、権限は600。sh の `.` と systemd の `EnvironmentFile=` の両方で読める。
- 削除の前に、`/`・`/usr`・`/etc`・`/var/lib`・`$HOME`・`$HOME/.config` などの重要なディレクトリでないこと、取得先が git の作業ツリーであることを確かめる。

## 設定値の決まり方

優先順位は `--set` > 環境変数 > 既存の設定ファイル > 既定値。

- 既存の設定ファイルの値は保持する。`install` の再実行・`update` で行うのは、スキーマに増えたキーの追記と、`--set`・環境変数で明示したキーの上書きだけ。
- `--set`・環境変数で受け付けるのは `config.schema` で宣言したキーだけ。未宣言キーの `--set` はエラー（タイプミスを防ぐ）。
- `required` で既定値が空のキーにどこからも値が無ければ、何も変更せずに止まる（検証は変更の前に行う）。
- 値に `'` と改行は使えない。値はログに出さず、キー名と、どの経路で決まったか（set・env・default）だけを出す。
- `--set` の値は `ps` やシェルの履歴に残る。秘匿値は環境変数（`sudo env KEY=… sh …`）か、設定ファイルへの直接の記入で渡す。

## `app.conf` の書式

シェルの代入文で、1行1キー。

```sh
APP_NAME='my-app'
INSTALL_MODE='system'
```

| キー | 必須 | 内容 |
|---|---|---|
| `APP_NAME` | ○ | 英小文字・数字・`-`、英小文字始まり |
| `INSTALL_MODE` | | `system`（既定）か `user` |
| `CTL_NAME` | | 常設コマンド名。既定は `<APP_NAME>-ctl`。アプリ自身のコマンド名とぶつかるときに変える |
| `CTL_SUBCOMMAND` | | 指定すると、`CTL_NAME` はアプリ自身のコマンドになり（`app_install` が置く）、更新・削除は `<CTL_NAME> <CTL_SUBCOMMAND> update` の形で呼ぶ。install.sh の `update`・`uninstall` もこの形で委譲する |
| `DATA_DIR` | | データディレクトリの絶対パス。`$HOME` を使ってよい（`main.sh` が実行時に評価する） |

`APP_NAME`・`INSTALL_MODE`・`CTL_NAME`・`CTL_SUBCOMMAND` は CI でも読むので、`KEY='値'` か `KEY=値` の形で、変数や式を使わずに書く。

## `config.schema` の書式

1行1キー、区切りは `|`。

```
KEY|既定値|required または optional|説明
```

- KEY は大文字英数字と `_`（英字始まり）。既定値と説明に `|` と改行は使えない。
- 説明は、設定ファイルへ追記するときに `# 説明` の行として書かれる。
- `#` で始まる行と空行は無視する。設定を持たないアプリなら空のファイルでよい。

## CI の動作

`release-installer.yml` は、すべてのブランチ・`v*` タグへの push と手動実行で動く。

1. `installer-check.yml`（プロジェクト固有の検査）を呼ぶ。失敗したらそこで止まる。
2. `install.sh` を生成し、`installer/*.sh` と生成物にシェルの構文検査と `shellcheck -S warning` をかける。
3. `install.sh`・`install.sh.sha256` を artifact `installer-<ブランチ・タグ名の / を - にしたもの>` として保存する。ジョブのサマリには、そのブランチ・タグを導入・切り替えるコマンドを出す。
4. `v*` タグなら GitHub Release に添付する（無ければ作る）。

`installer-check.yml` は `workflow_call` で呼ばれ、呼び出し側から `contents: read`・`packages: read` の権限と secrets を受け取る。GitHub Packages からの依存の取得などはここに書ける。

## README に書くこと

- 導入（system 方式。user 方式なら `sudo` を外す）:
  ```sh
  curl -fsSL https://github.com/<owner>/<repo>/releases/latest/download/install.sh | sudo sh -s -- install --set KEY=VALUE
  ```
- 版を固定した導入: `…/releases/download/<タグ>/install.sh`
- ブランチの導入・切り替え: `install --ref <ブランチ名>`、導入後は `<アプリ名>-ctl update --ref <名前>`
- 更新・状態・一覧・削除: `<アプリ名>-ctl update` / `status` / `refs` / `uninstall [--purge]`
- 設定ファイルの場所と、キーの一覧（`config.schema` の内容）。手編集した後の反映方法（サービスの再起動など、アプリ次第）
- 秘匿値は `--set` ではなく環境変数か設定ファイルで渡すこと
