#!/bin/sh
# 責務: assets のインストーラ一式を、使い捨てのリポジトリ（file://）へ配置して install.sh を生成し、
#       導入・設定・更新・ブランチ/タグの切り替え・削除の各動作を実際に実行して確かめる。
# 使い方: sudo sh tests/e2e.sh system   （root権限。/etc・/var/lib・/usr/local/bin に e2eapp-bcb の導入物を作り、最後に消す）
#         sh tests/e2e.sh user          （一般ユーザー。HOME を一時ディレクトリに差し替えて実行する）
#         第2引数に sub を付けると、常設コマンドをアプリ自身のコマンドのサブコマンド（CTL_SUBCOMMAND=self）にして同じ検査をする
# 出力: 検査ごとに ok / NG を1行。NG が1つでもあれば終了コード1。

set -eu

MODE=${1:-}
VARIANT=${2:-}
case "$VARIANT" in
  ""|sub) ;;
  *) echo "第2引数は sub か省略です: $VARIANT" 1>&2; exit 1 ;;
esac
case "$MODE" in
  system) [ "$(id -u)" -eq 0 ] || { echo "system は root で実行してください" 1>&2; exit 1; } ;;
  user) [ "$(id -u)" -ne 0 ] || { echo "user は一般ユーザーで実行してください" 1>&2; exit 1; } ;;
  *) echo "使い方: sh $0 <system|user> [sub]" 1>&2; exit 1 ;;
esac

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
APP=e2eapp-bcb
SRC="$WORK/src"
URL="file://$SRC"
FAIL=0

if [ "$MODE" = user ]; then
  export HOME="$WORK/home"
  mkdir -p "$HOME"
  export PATH="$HOME/.local/bin:$PATH"
  CONF_DIR="$HOME/.config/$APP"; STATE_DIR="$HOME/.local/state/$APP-installer"
  DATA_DIR="$HOME/.local/state/$APP"; BIN_DIR="$HOME/.local/bin"
else
  CONF_DIR="/etc/$APP"; STATE_DIR="/var/lib/$APP-installer"
  DATA_DIR="/var/lib/$APP"; BIN_DIR=/usr/local/bin
fi
export E2EAPP_BCB_DIR="$WORK/install"
DIR=$E2EAPP_BCB_DIR
CONF="$CONF_DIR/$APP.env"
STATE="$STATE_DIR/state"
if [ "$VARIANT" = sub ]; then
  CTL="$BIN_DIR/$APP"
  CTLRUN="'$CTL' self"
else
  CTL="$BIN_DIR/$APP-ctl"
  CTLRUN="'$CTL'"
fi
ctl() { if [ "$VARIANT" = sub ]; then "$CTL" self "$@"; else "$CTL" "$@"; fi; }

cleanup() {
  rm -rf "$CONF_DIR" "$STATE_DIR" "$DATA_DIR" "$CTL" "$BIN_DIR/$APP-hello" "$WORK"
}
trap cleanup EXIT
cleanup_before() { rm -rf "$CONF_DIR" "$STATE_DIR" "$DATA_DIR" "$CTL" "$BIN_DIR/$APP-hello"; }
cleanup_before

ok() { echo "ok  $*"; }
ng() { echo "NG  $*"; FAIL=1; }
check() { _d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$_d"; else ng "$_d"; fi; }
check_not() { _d=$1; shift; if "$@" >/dev/null 2>&1; then ng "$_d"; else ok "$_d"; fi; }
state_ref() { sed -n "s/^REF='\(.*\)'\$/\1/p" "$STATE"; }
state_commit() { sed -n "s/^COMMIT='\(.*\)'\$/\1/p" "$STATE"; }
conf_val() { sed -n "s/^$1='\(.*\)'\$/\1/p" "$CONF"; }
g() { git -C "$SRC" -c user.name=e2e -c user.email=e2e@example.test "$@"; }

mkdir -p "$SRC"
git -C "$SRC" -c init.defaultBranch=main init -q
sh "$ROOT/scripts/sync.sh" "$SRC" >/dev/null
printf "APP_NAME='%s'\nINSTALL_MODE='%s'\n" "$APP" "$MODE" > "$SRC/installer/app.conf"
[ "$VARIANT" != sub ] || printf "CTL_NAME='%s'\nCTL_SUBCOMMAND='self'\n" "$APP" >> "$SRC/installer/app.conf"
cat > "$SRC/installer/config.schema" <<'EOF'
REQ||required|必須の値
OPT|default-opt|optional|任意の値
EOF
cat > "$SRC/installer/app.sh" <<'EOF'
# shellcheck shell=sh disable=SC2154

app_install() {
  [ -z "${E2E_HOOK_FAIL:-}" ] || die "フックを失敗させる"
  # shellcheck source=/dev/null
  . "$CONF_FILE"
  mkdir -p "$DATA_DIR"
  printf '%s %s\n' "$REQ" "$OPT" > "$DATA_DIR/installed"
  printf '#!/bin/sh\necho hello\n' > "$BIN_DIR/$APP-hello"
  chmod 755 "$BIN_DIR/$APP-hello"
  if [ -n "$CTL_SUBCOMMAND" ]; then
    printf '#!/bin/sh\n[ "$1" = self ] || { echo hello; exit 0; }\nshift\nexec sh %s "$@"\n' "'$DIR/installer/main.sh'" > "$BIN_DIR/$APP"
    chmod 755 "$BIN_DIR/$APP"
  fi
}

app_uninstall() {
  rm -f "$BIN_DIR/$APP-hello"
}

app_purge() {
  :
}
EOF
g add -A; g commit -qm c1
C1=$(g rev-parse HEAD)
g tag v1

build() { sh "$SRC/installer/build-bootstrap.sh" "$1" "$2" "$URL"; }
build refs/heads/main "$C1" > "$WORK/install-c1.sh"
I1="$WORK/install-c1.sh"

echo "--- 生成"
check "生成した install.sh の構文が正しい" sh -n "$I1"
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck（コア・app.sh・生成物）" shellcheck -S warning "$SRC/installer/main.sh" "$SRC/installer/build-bootstrap.sh" "$SRC/installer/app.sh" "$I1"
fi
check_not "不正な REF では生成しない" build main "$C1"
check_not "ひな形そのものは実行できない" sh "$SRC/installer/bootstrap.sh.tmpl" install
cp "$SRC/installer/app.conf" "$WORK/app.conf.bak"
printf "APP_NAME='%s'\nINSTALL_MODE='both'\n" "$APP" > "$SRC/installer/app.conf"
check_not "app.conf の INSTALL_MODE が不正なら生成しない" build refs/heads/main "$C1"
cp "$WORK/app.conf.bak" "$SRC/installer/app.conf"
if [ "$VARIANT" = sub ]; then
  check "生成した install.sh に CTL_SUBCOMMAND が埋め込まれる" grep -q "^CTL_SUBCOMMAND='self'\$" "$I1"
fi

echo "--- 権限"
chmod 755 "$WORK"
if [ "$MODE" = system ]; then
  check "system 方式は一般ユーザーでは実行できない" sh -c "su nobody -s /bin/sh -c \"sh '$I1' install --set REQ=a\" 2>&1 | grep -q 'root権限で実行してください'"
else
  mkdir -p "$WORK/fakeroot"
  printf '#!/bin/sh\necho 0\n' > "$WORK/fakeroot/id"
  chmod 755 "$WORK/fakeroot/id"
  check "user 方式は root では実行できない" sh -c "PATH='$WORK/fakeroot':\"\$PATH\" sh '$I1' install --set REQ=a 2>&1 | grep -q '一般ユーザーで実行してください'"
fi

echo "--- install と設定"
check_not "必須キーが無い install は失敗する" sh "$I1" install
check_not "失敗した install は設定・導入メタ情報を作らない" test -e "$CONF" -o -e "$STATE"
check_not "フックが失敗した install は失敗する" env E2E_HOOK_FAIL=1 sh "$I1" install --set REQ=a
check_not "フックが失敗した install は導入メタ情報・常設コマンドを作らない" test -e "$STATE" -o -e "$CTL"
check "フックが失敗しても --set の値は設定ファイルに残る" test "$(conf_val REQ)" = a
check "install --set で導入できる" sh "$I1" install --set REQ=a
check "設定ファイルの権限が600" test "$(stat -c %a "$CONF")" = 600
check "app_install が設定値を読める" test "$(cat "$DATA_DIR/installed")" = "a default-opt"
check "常設コマンドが置かれる" test -x "$CTL"
check "導入メタ情報の REF が完全名" test "$(state_ref)" = refs/heads/main
sed -i "s/^OPT=.*/OPT='hand'/" "$CONF"
check "install の再実行が通る" sh "$I1" install
check "手で編集した値が保持される" test "$(conf_val OPT)" = hand
check "環境変数で上書きできる" env OPT=env sh "$I1" install
check "環境変数の値が反映される" test "$(conf_val OPT)" = env
check "--set と環境変数の両方を指定できる" env OPT=env sh "$I1" install --set OPT=set
check "--set が環境変数より優先される" test "$(conf_val OPT)" = set
check_not "未宣言キーの --set は失敗する" sh "$I1" install --set NOPE=x
check_not "' を含む値の --set は失敗する" sh "$I1" install --set "REQ=a'b"

echo "--- update"
printf 'NEWKEY|nv|optional|追加した値\n' >> "$SRC/installer/config.schema"
g commit -qam c2
C2=$(g rev-parse HEAD)
check "常設コマンドで update できる" ctl update
check "update で最新のコミットへ追従する" test "$(state_commit)" = "$C2"
check "スキーマに増えたキーが追記される" test "$(conf_val NEWKEY)" = nv
g commit -q --allow-empty -m c3
C3=$(g rev-parse HEAD)
check "古い install.sh の update が通る" sh "$I1" update
check "古い install.sh の update も最新へ追従する（埋め込みコミットに戻らない）" test "$(state_commit)" = "$C3"
check_not "フックが失敗した update は失敗する" env E2E_HOOK_FAIL=1 sh -c "$CTLRUN update --ref v1"
check "フックが失敗した update は導入メタ情報の参照を変えない" test "$(state_ref)" = refs/heads/main

echo "--- ブランチ・タグ"
g checkout -qb feat/x
g commit -q --allow-empty -m feat
CF=$(g rev-parse HEAD)
g checkout -q main
g branch dup
g tag dup
check "install --ref でブランチを導入できる" sh "$I1" install --ref feat/x
check "ブランチの先頭が入る" test "$(state_commit)" = "$CF"
check "--ref で導入したブランチを記録する" test "$(state_ref)" = refs/heads/feat/x
check "update --ref でタグへ切り替えられる" ctl update --ref v1
check "タグのコミットに切り替わる" test "$(state_commit)" = "$C1"
check "タグを完全名で記録する" test "$(state_ref)" = refs/tags/v1
check "update --ref でブランチへ戻せる" ctl update --ref main
check "ブランチへの切り替えを記録する" test "$(state_ref)" = refs/heads/main
check_not "存在しない --ref は失敗する" ctl update --ref nope
check "存在しない --ref は導入メタ情報を変えない" test "$(state_ref)" = refs/heads/main
check_not "ブランチとタグが同名なら失敗する" ctl update --ref dup
check "同名でも完全名なら通る" ctl update --ref refs/tags/dup
check "refs でブランチとタグを一覧できる" sh -c "$CTLRUN refs | grep -q '^tag	v1\$' && $CTLRUN refs | grep -q '^branch	feat/x\$'"
check "status に参照が出る" sh -c "$CTLRUN status | grep -q 'dup（tag）'"

echo "--- uninstall"
check "uninstall できる" ctl uninstall
check "取得先・常設コマンド・アプリの導入物が消える" sh -c "! test -e '$DIR' && ! test -e '$CTL' && ! test -e '$BIN_DIR/$APP-hello'"
check "設定とデータは残る" sh -c "test -f '$CONF' && test -d '$DATA_DIR'"
check "残った設定で再 install できる（--set 不要）" sh "$I1" install
check "再 install で設定が再利用される" test "$(conf_val REQ)" = a
check "install.sh 経由で uninstall --purge できる" sh "$I1" uninstall --purge
check "--purge で設定・データ・導入メタ情報が消える" sh -c "! test -e '$CONF_DIR' && ! test -e '$DATA_DIR' && ! test -e '$STATE_DIR'"
check_not "未導入での update は失敗する" sh "$I1" update

[ "$FAIL" -eq 0 ] && echo "すべて ok（$MODE $VARIANT）" || echo "NG あり（$MODE $VARIANT）"
exit "$FAIL"
