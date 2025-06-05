#!/usr/bin/env bash
#=========================================================
# NAS同期（前日の日付ディレクトリ内のファイルをフラットに転送）
#=========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [ -f "$ENV_FILE" ]; then
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

# === 環境変数の読込とデフォルト設定 ===
NAS_DEST="${NAS_DEST:-rsync://NAS/timelapse}"
LOG_DIR="/home/pi/timelapse-system/log/nas"
LOG_FILE="${LOG_DIR}/sync_nas_$(date '+%F').log"

mkdir -p "$LOG_DIR"

# 前日の日付ディレクトリ名を生成
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
LOCAL_DIR="/home/pi/timelapse-system/archived/$YESTERDAY"

# 前日の日付ディレクトリが存在しない場合は終了
if [ ! -d "$LOCAL_DIR" ]; then
  echo "[$(date '+%F %T')] ℹ️ No directory for yesterday ($YESTERDAY)" >> "$LOG_FILE"
  exit 0
fi

{
  echo "[$(date '+%F %T')] 🚀 Starting NAS sync for $YESTERDAY..."
  START_TIME=$(date +%s)

  # 前日ディレクトリ内のファイル一覧を生成してシャッフル
  TMPFILE=$(mktemp)
  cd "$LOCAL_DIR"
  find . -type f -name '*.jpg' | shuf > "$TMPFILE"

  # バッチサイズとスリープ時間の設定
  BATCH_SIZE=100  # 一度に転送するファイル数
  SLEEP_SEC=5    # バッチ間のスリープ時間(秒)
  BWLIMIT=5000   # 帯域制限(KB/s)

  # バッチ処理で分割転送
  total_files=$(wc -l < "$TMPFILE")
  batch_num=0
  while IFS= read -r batch; do
    batch_num=$((batch_num + 1))
    batch_tmpfile=$(mktemp)
    echo "$batch" > "$batch_tmpfile"

    echo "[$(date '+%F %T')] 📦 Processing batch $batch_num (${BATCH_SIZE} files max)"

    # 最適化したrsyncオプションで転送
    if rsync -av --files-from="$batch_tmpfile" \
             --bwlimit="${BWLIMIT}" \
             --compress \
             --compress-level=5 \
             --partial \
             --progress \
             "$LOCAL_DIR/" "$NAS_DEST/"; then
      echo "[$(date '+%F %T')] ✅ Batch $batch_num successful"
    else
      echo "[$(date '+%F %T')] ❌ Batch $batch_num failed"
    fi

    rm -f "$batch_tmpfile"
    
    # 次のバッチの前に待機
    echo "[$(date '+%F %T')] 💤 Sleeping for ${SLEEP_SEC}s..."
    sleep "$SLEEP_SEC"

  done < <(split -l "$BATCH_SIZE" "$TMPFILE")

  rm -f "$TMPFILE"

  # 50日以上前のディレクトリを削除
  cd "$(dirname "$LOCAL_DIR")"
  echo "[$(date '+%F %T')] 🗑 Cleaning up old directories (50+ days)..."
  find . -mindepth 1 -maxdepth 1 -type d -mtime +50 -print0 | while IFS= read -r -d '' dir; do
    if rm -rf "$dir"; then
      echo "[$(date '+%F %T')] 🗑 Removed old directory: $dir"
    else
      echo "[$(date '+%F %T')] ⚠️ Failed to remove directory: $dir"
    fi
  done

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  echo "[$(date '+%F %T')] ⏱ Duration: ${DURATION}s"
  echo "[$(date '+%F %T')] ✅ NAS sync job finished"
  echo
} >> "$LOG_FILE" 2>&1