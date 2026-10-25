# 検証の進め方

コアの動作（設定の優先順位・`--ref` の解決・導入メタ情報・削除範囲など）は、このスキルの `tests/e2e.sh` で確かめてある。プロジェクトで確かめるのは、**生成が通ること**と、**フックが正しく導入・再適用・削除すること**である。

## 1. 生成と静的検査

```sh
sh installer/build-bootstrap.sh refs/heads/main "$(git rev-parse HEAD)" "file://$PWD" > /tmp/install.sh
sh -n /tmp/install.sh
shellcheck -S warning installer/main.sh installer/build-bootstrap.sh installer/app.sh /tmp/install.sh
```

`app.sh` で `. "$CONF_FILE"` を使う行には、`# shellcheck source=/dev/null` を付ける。

## 2. 使い捨ての環境で実際に導入する

追跡外のファイル（`.env` など）が無い、使い捨てにできる環境で行う。ユーザーが検証用のマシンを用意しているなら、それを使う。

- 取得元には、検証したいコミットを含むリポジトリを `file://` で渡す。手元の未 push のコミットを試すときは、そのリポジトリを検証環境へコピーし、そこで `build-bootstrap.sh` を実行する。
- system 方式は root で、user 方式は一般ユーザーで実行する。

確かめること:

| 観点 | 確かめ方 |
|---|---|
| 必須設定の検証 | 必須キー無しの `install` が、何も変更せずに失敗する |
| 導入 | `install --set …` の後、アプリが動く（サービスが起動している、コマンドが使えるなど） |
| 冪等性 | `install` をもう一度実行しても失敗せず、状態が変わらない（重複した登録や二重起動がない） |
| 設定の反映 | 設定ファイルを手で編集して `install` を再実行すると、値が保持され、アプリに反映される |
| 更新 | 新しいコミット（フックや設定キーを変えたもの）を作って `<アプリ名>-ctl update` を実行すると、新しいフックで再適用される |
| 削除 | `uninstall` の後、`$DIR` の外に置いた導入物が残っていない。設定・データは残る |
| 完全削除 | `uninstall --purge` の後、`app_purge` の対象を含めて何も残っていない |
| 再導入 | `uninstall` の後の `install` が、残った設定で動く |

systemd・コンテナなど、検証環境で代わりのものに置き換えられない処理は、実際にそれが動く環境で一度は通す。`/bin/sh` が dash の環境（Debian・Ubuntu）で通すと、bash 固有の書き方を拾える。

## 3. ワークフロー

`actionlint` があれば `.github/workflows/release-installer.yml` と `installer-check.yml` にかける。無ければ YAML としての構文だけでも確かめる。push の後は、Actions のジョブのサマリに導入コマンドが出ていることと、artifact に `install.sh` があることを確かめる。
