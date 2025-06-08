#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/home/pi/timelapse-system/log/cron.log"
echo "[$(date '+%F %T')] 🧹 [cleanup] Starting cleanup of split files..." >> "$LOG_FILE"

# /tmp の sync_batch_* 削除
TMP_FILES=(/tmp/sync_batch_*)
TMP_DELETE_COUNT=0
for f in "${TMP_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    TMP_DELETE_COUNT=$((TMP_DELETE_COUNT + 1))
  fi
done

if [[ $TMP_DELETE_COUNT -gt 0 ]]; then
  echo "[$(date '+%F %T')] 🗑 [cleanup] Deleted $TMP_DELETE_COUNT /tmp/sync_batch_* files." >> "$LOG_FILE"
else
  echo "[$(date '+%F %T')] ℹ️ [cleanup] No /tmp/sync_batch_* files found." >> "$LOG_FILE"
fi

# archived 以下の xaa,xab... 削除
XA_DELETE_COUNT=0
while IFS= read -r -d '' f; do
  rm -f "$f"
  XA_DELETE_COUNT=$((XA_DELETE_COUNT + 1))
done < <(find /home/pi/timelapse-system/archived -type f -regex '.*/xa[a-z]+' -print0)

if [[ $XA_DELETE_COUNT -gt 0 ]]; then
  echo "[$(date '+%F %T')] 🗑 [cleanup] Deleted $XA_DELETE_COUNT xaa/xab/... files." >> "$LOG_FILE"
else
  echo "[$(date '+%F %T')] ℹ️ [cleanup] No xaa/xab/... files found." >> "$LOG_FILE"
fi

echo "[$(date '+%F %T')] ✅ [cleanup] Cleanup completed." >> "$LOG_FILE"
