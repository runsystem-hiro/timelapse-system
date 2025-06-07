#!/usr/bin/env bash
set -euo pipefail

SRC="/home/pi/timelapse-system/images"
DEST="/home/pi/timelapse-system/archived"
LOG="/home/pi/timelapse-system/log/move_archived.log"
MOVE_LIMIT=30

YESTERDAY=$(date -d "yesterday" +%Y%m%d)

# 対象ファイルを抽出
files=($(find "$SRC" -type f -name "${YESTERDAY}_*.jpg"))

# 処理対象が0件ならログ出力せず終了
if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

# 対象がある場合のみログを出す
echo "$(date '+%F %T') DEBUG: YESTERDAY=$YESTERDAY" >> "$LOG"

# カウント初期化
count=0

# 最大MOVE_LIMIT件まで処理
for file in "${files[@]}"; do
  if [ "$count" -ge "$MOVE_LIMIT" ]; then
    break
  fi

  filename=$(basename "$file")
  filedate=${filename:0:8}
  datedir="${filedate:0:4}-${filedate:4:2}-${filedate:6:2}"
  destdir="$DEST/$datedir"

  mkdir -p "$destdir"
  echo "$(date '+%F %T') DEBUG: Moving $file to $destdir/" >> "$LOG"

  if mv -f "$file" "$destdir/"; then
    count=$((count + 1))
    echo "$(date '+%F %T') DEBUG: Successfully moved file ($count/$MOVE_LIMIT)" >> "$LOG"
  else
    echo "$(date '+%F %T') ERROR: Failed to move $file" >> "$LOG"
  fi
done

# 空ディレクトリ掃除
find "$SRC" -type d -empty -delete
