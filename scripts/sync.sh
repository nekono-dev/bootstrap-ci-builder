#!/bin/sh
# 責務: 対象リポジトリへインストーラ一式を配置する。コア（assets/core）は毎回上書きし、アプリ側のひな形（assets/app）は無いときだけ置く。
# 初回の導入にも、このスキルの更新に追従するときにも、同じコマンドを使う。
# 使い方: sh scripts/sync.sh <対象リポジトリのパス>
# 出力: 配置したファイルごとに「上書き」「作成」「既存のため変更なし」を1行ずつ出す。

set -eu

[ "$#" -eq 1 ] || { echo "使い方: sh $0 <対象リポジトリのパス>" 1>&2; exit 1; }
TARGET=$1
[ -d "$TARGET" ] || { echo "対象のディレクトリがありません: $TARGET" 1>&2; exit 1; }
ASSETS=$(CDPATH='' cd -- "$(dirname -- "$0")/../assets" && pwd)

place() {
  _src=$1; _rel=$2; _mode=$3
  _dst="$TARGET/$_rel"
  mkdir -p "$(dirname -- "$_dst")"
  if [ "$_mode" = core ]; then
    if [ -f "$_dst" ] && cmp -s "$_src" "$_dst"; then
      echo "変更なし: $_rel"
    elif [ -f "$_dst" ]; then
      cp "$_src" "$_dst"; echo "上書き:   $_rel"
    else
      cp "$_src" "$_dst"; echo "作成:     $_rel"
    fi
  elif [ -e "$_dst" ]; then
    echo "既存のため変更なし: $_rel"
  else
    cp "$_src" "$_dst"; echo "作成:     $_rel"
  fi
}

for _mode in core app; do
  (cd "$ASSETS/$_mode" && find . -type f | sed 's|^\./||' | sort) | while IFS= read -r _rel; do
    place "$ASSETS/$_mode/$_rel" "$_rel" "$_mode"
  done
done
