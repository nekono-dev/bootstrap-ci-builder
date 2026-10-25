# bootstrap-ci-builder

GitHub のブランチ・タグごとに、そのコミットに固定したインストーラ（`install.sh`）を GitHub Actions で生成・頒布し、導入後は常設コマンド（`<アプリ名>-ctl`）で更新・ブランチ/タグの切り替え・削除を行えるようにする仕組みを、リポジトリへ整備する Claude Code のスキル（プラグイン）。

利用者は次の1行で導入し、以後は常設コマンドで更新する。

```sh
curl -fsSL https://github.com/<owner>/<repo>/releases/latest/download/install.sh | sudo sh -s -- install
sudo <アプリ名>-ctl update --ref feat/x
```

## 導入

```
/plugin marketplace add nekono-dev/claude-plugins
/plugin install bootstrap-ci-builder@nekono-dev
```

「install.sh を作りたい」「curl でインストールできるようにしたい」といった依頼でスキルが使われる。

## 構成

| パス | 内容 |
|---|---|
| `SKILL.md` | スキル本体（作業の進め方・フックの契約） |
| `references/spec.md` | インストーラの仕様（サブコマンド・配置先・設定・書式・README に書くこと） |
| `references/verification.md` | 利用先での検証の進め方 |
| `assets/core/` | 全プロジェクト共通のコア。利用先では編集せず、`scripts/sync.sh` で上書きする |
| `assets/app/` | アプリ側のひな形（`app.conf`・`app.sh`・`config.schema`・`installer-check.yml`）。利用先で書き換える |
| `scripts/sync.sh` | 利用先へコアを上書きし、アプリ側のひな形を無いときだけ置く |
| `tests/e2e.sh` | コアを使い捨てのリポジトリで実際に動かす検査 |
| `evals/` | スキルの評価ケース（`claude plugin eval` の形式） |

## 開発

コアを変えたら、Debian 系の環境で両方の方式の E2E を通す（CI の `test` ワークフローでも実行される）。

```sh
sh tests/e2e.sh user
sudo sh tests/e2e.sh system
```

system 方式は `/etc/e2eapp-bcb` などに導入物を作り、終了時に消す。

## ライセンス

[Unlicense](LICENSE)
