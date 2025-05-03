#!/usr/bin/env bash
#=========================================================
# NAS同期後、50日以上前の画像をローカルから削除（同期成功時のみ）
#=========================================================
set -euo pipefail

LOCAL_DIR="/home/pi/timelapse-system/archived/"
NAS_DEST="rsync://NAS/timelapse"
LOG_FILE="/home/pi/timelapse-system/log/sync_nas.log"

{
  echo "[`date '+%F %T'`] Starting NAS sync..."

  # rsync実行（--timeoutや--contimeoutで停止状態のNASに対しても制御可能）
  if rsync -rtv --progress --omit-dir-times "${LOCAL_DIR}" "${NAS_DEST}"; then
    echo "[`date '+%F %T'`] NAS sync successful."

    # 同期成功時のみ、50日以上前のjpgを削除
    find "${LOCAL_DIR}" -type f -name '*.jpg' -mtime +50 -print -delete

    # 空ディレクトリ削除
    find "${LOCAL_DIR}" -type d -empty -delete

    echo "[`date '+%F %T'`] Deleted jpg files older than 50 days."
  else
    echo "[`date '+%F %T'`] ❌ NAS sync failed — skipping deletion."
  fi

  echo
} >> "${LOG_FILE}" 2>&1
