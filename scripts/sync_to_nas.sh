#!/usr/bin/env bash
#=========================================================
# NAS同期後、50日以上前の画像をローカルから削除（同期成功時のみ）
#=========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [ -f "$ENV_FILE" ]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

NAS_DEST="${NAS_DEST:-rsync://NAS/timelapse}"
LOCAL_DIR="/home/pi/timelapse-system/archived/"
LOG_FILE="/home/pi/timelapse-system/log/sync_nas.log"

{
  echo "[`date '+%F %T'`] Starting NAS sync..."

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
