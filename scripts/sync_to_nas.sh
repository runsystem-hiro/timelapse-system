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

# === 処理対象日（引数または昨日）を取得 ===
TARGET_DATE="${1:-$(date -d "yesterday" +%Y-%m-%d)}"

# === 環境変数とディレクトリ設定 ===
NAS_DEST="${NAS_DEST:-rsync://NAS/timelapse}"
LOG_DIR="/home/pi/timelapse-system/log/nas"
mkdir -p "$LOG_DIR"

# === ログと同期対象ディレクトリの構成 ===
LOG_FILE="${LOG_DIR}/sync_nas_$(date '+%F').log"
LOCAL_DIR="/home/pi/timelapse-system/archived/$TARGET_DATE"

# === 処理チューニングパラメータ ===
BATCH_SIZE="${BATCH_SIZE:-100}"
SLEEP_SEC="${SLEEP_SEC:-5}"
BWLIMIT="${BWLIMIT:-5000}"

# 前日の日付ディレクトリが存在しない場合は終了
if [ ! -d "$LOCAL_DIR" ]; then
  echo "[$(date '+%F %T')] ℹ️ No directory for yesterday ($TARGET_DATE)" >> "$LOG_FILE"
  exit 0
fi

{
  echo "[$(date '+%F %T')] 🚀 Starting NAS sync for $TARGET_DATE..."
  START_TIME=$(date +%s)

  # 前日ディレクトリ内のファイル一覧を生成してシャッフル
  TMPFILE=$(mktemp)
  cd "$LOCAL_DIR"
  find . -type f -name '*.jpg' | shuf > "$TMPFILE"

  # ファイルの存在確認
  if [ ! -s "$TMPFILE" ]; then
    echo "[$(date '+%F %T')] ⚠️ No JPG files found in $LOCAL_DIR"
    rm -f "$TMPFILE"
    exit 0
  fi

  # NAS接続テスト追加
  echo "[$(date '+%F %T')] 🔗 Testing NAS connection..."
  for i in {1..3}; do
    if rsync --timeout=30 "$NAS_DEST/" > /dev/null 2>&1; then
      echo "[$(date '+%F %T')] ✅ NAS connection successful"
      break
    else
      if [ $i -eq 3 ]; then
        echo "[$(date '+%F %T')] ❌ Cannot connect to NAS after 3 attempts: $NAS_DEST"
        exit 1
      fi
      echo "[$(date '+%F %T')] ⚠️ Retry NAS connection test ($i/3)..."
      sleep 5
    fi
  done

  # ファイル数のログ出力を追加
  total_files=$(wc -l < "$TMPFILE")
  echo "[$(date '+%F %T')] 📁 Found $total_files JPG files to sync"
  
  # バッチ処理で分割転送
  batch_num=0
  
  # 一時ディレクトリを作成
  batch_dir=$(mktemp -d)
  split -l "$BATCH_SIZE" "$TMPFILE" "$batch_dir/batch."

  # 分割されたファイルを処理
  for batch_file in "$batch_dir"/batch.*; do
    batch_num=$((batch_num + 1))
    echo "[$(date '+%F %T')] 📦 Processing batch $batch_num (${BATCH_SIZE} files max)"

    # 最適化したrsyncオプションで転送
    if rsync -av --no-t --files-from="$batch_file" \
             --bwlimit="${BWLIMIT}" \
             --compress \
             --compress-level=5 \
             --partial \
             --timeout=300 \
             "$LOCAL_DIR/" "$NAS_DEST/" 2>&1; then
      files_count=$(wc -l < "$batch_file")
      echo "[$(date '+%F %T')] ✅ Batch $batch_num successful ($files_count files)"
    else
      error_code=$?
      echo "[$(date '+%F %T')] ❌ Batch $batch_num failed with error code: $error_code"
      echo "[$(date '+%F %T')] 🔄 Retrying batch $batch_num after 30s pause..."
      sleep 30
      if rsync -av --no-t --files-from="$batch_file" \
               --bwlimit="${BWLIMIT}" \
               --compress \
               --compress-level=5 \
               --partial \
               --timeout=300 \
                "$LOCAL_DIR/" "$NAS_DEST/" 2>&1; then
        files_count=$(wc -l < "$batch_file")
        echo "[$(date '+%F %T')] ✅ Retry successful for batch $batch_num ($files_count files)"
      else
        echo "[$(date '+%F %T')] ❌ Retry failed for batch $batch_num"
      fi
    fi
    
    # 次のバッチの前に待機
    echo "[$(date '+%F %T')] 💤 Sleeping for ${SLEEP_SEC}s..."
    sleep "$SLEEP_SEC"
  done

  # 一時ディレクトリとファイルを削除
  rm -rf "$batch_dir"
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
  echo "[$(date '+%F %T')] 📦 Total files attempted: $total_files"
  echo "[$(date '+%F %T')] ✅ NAS sync job finished"
  echo
} >> "$LOG_FILE" 2>&1