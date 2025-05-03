#!/usr/bin/env bash
#=========================================================
#  timelapse-system : ローカル同期スクリプト（NAS なし検証用）
#=========================================================
set -euo pipefail

SRC="/home/pi/timelapse-system/images/"
DEST="/home/pi/timelapse-system/archived/"
mkdir -p "${DEST}"

# 画像を archived/ へ移動（コピー後に元を削除）
rsync -av --remove-source-files "${SRC}" "${DEST}"

# images/ 直下の空フォルダは残しつつ、中の空ディレクトリだけ削除
find "${SRC}" -mindepth 1 -type d -empty -delete

echo "[`date '+%F %T'`] Synced to ${DEST}"
