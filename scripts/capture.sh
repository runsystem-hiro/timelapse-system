#!/usr/bin/env bash
set -euo pipefail

# ==== 処理スキップ条件 ====
if pgrep -f mjpeg_server.py >/dev/null; then
  echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') mjpeg_server 実行中のため撮影スキップ" >> /home/pi/timelapse-system/log/cron.log
  exit 0
fi

# ==== 撮影条件 ====
ROTATION=0
VFLIP=false
HFLIP=false
FOCUS_POS=0.8
AWB_OPT="--awb fluorescent"
DENOISE_OPT="--denoise cdn_off"
ROT_OPT=""
AUTO_MODE=false

[[ $ROTATION != 0 ]] && ROT_OPT+=" --rotation $ROTATION"
[[ $VFLIP == true ]] && ROT_OPT+=" --vflip"
[[ $HFLIP == true ]] && ROT_OPT+=" --hflip"

# ==== 各種パスとファイル名 ====
IMG_DIR="/home/pi/timelapse-system/images"
LOGFILE="/home/pi/timelapse-system/log/brightness_$(date '+%Y-%m').csv"
CRONLOG="/home/pi/timelapse-system/log/cron.log"
mkdir -p "$IMG_DIR"

STAMP=$(date +"%Y%m%d_%H%M%S")
OUTFILE="${IMG_DIR}/${STAMP}.jpg"
TMPFILE="/tmp/meancheck.jpg"

# ==== 時間帯分類 ====
HOUR=$(date +"%H")
HOUR=$((10#$HOUR))

case $HOUR in
  04|05) TIME_INFO="early_morning" ;;
  06|07|08|09) TIME_INFO="morning" ;;
  10|11|12|13) TIME_INFO="midday" ;;
  14|15|16|17) TIME_INFO="afternoon" ;;
  18|19|20|21) TIME_INFO="evening" ;;
  *) TIME_INFO="night" ;;
esac

# ==== 明るさ測定（仮撮影） ====
libcamera-jpeg --nopreview --width 640 --height 360 --quality 50 \
  $AWB_OPT $DENOISE_OPT --lens-position "$FOCUS_POS" \
  -o "$TMPFILE" > /dev/null 2>&1 || true

MEAN=$(identify -format "%[fx:mean]" "$TMPFILE" 2>/dev/null || echo "n/a")
rm -f "$TMPFILE"

# ==== 明るさに基づく撮影条件 ====
if [[ "$MEAN" != "n/a" ]] && (( $(echo "$MEAN >= 0.15" | bc -l) )); then
  AUTO_MODE=false
  SHUTTER_OPT="--shutter 10000"
  GAIN_OPT="--gain 3.0"
  METER_OPT="--metering centre"
else
  AUTO_MODE=true
  EV_OPT="--ev 0"
  METER_OPT="--metering centre"
fi

# ==== 撮影本番（最大2回リトライ） ====
START_TIME=$(date +%s.%N)
SUCCESS=false
for i in {1..2}; do
  if $AUTO_MODE; then
    if OUTPUT=$(libcamera-jpeg --nopreview=on --width 2304 --height 1296 --quality 90 \
      $AWB_OPT $EV_OPT $METER_OPT $DENOISE_OPT \
      --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE" 2>&1); then
      SUCCESS=true
      break
    fi
  else
    if OUTPUT=$(libcamera-jpeg --nopreview=on --width 2304 --height 1296 --quality 90 \
      $AWB_OPT $METER_OPT $DENOISE_OPT $SHUTTER_OPT $GAIN_OPT \
      --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE" 2>&1); then
      SUCCESS=true
      break
    fi
  fi
  sleep 1
  echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') 撮影失敗のためリトライ中..." >> "$CRONLOG"
done

# ==== 明るさ取得（本番画像） ====
if ! $SUCCESS; then
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') 撮影失敗（リトライ2回）: $OUTPUT" >> "$CRONLOG"
  OUTFILE="N/A"
  MEAN_FINAL="n/a"
else
  MEAN_FINAL=$(identify -format "%[fx:mean]" "$OUTFILE" 2>/dev/null || echo "n/a")
fi

# ==== 撮影モード判定 ====
MODE_STR=$([[ $AUTO_MODE == true ]] && echo "auto" || echo "manual")

# ==== CSV出力（失敗時も含む） ====
SHUTTER_GAIN=$([[ $AUTO_MODE == true ]] && echo "auto,auto" || echo "${SHUTTER_OPT#--shutter },${GAIN_OPT#--gain }")
EV_STR=$([[ $AUTO_MODE == true ]] && echo "${EV_OPT#--ev }" || echo "n/a")

echo "$(date '+%Y-%m-%d %H:%M:%S'),indoor,$MODE_STR,$TIME_INFO,$SHUTTER_GAIN,$OUTFILE,$MEAN_FINAL,$EV_STR" >> "$LOGFILE"

# ==== 明るさ取得失敗ログ ====
if [[ "$MEAN_FINAL" == "n/a" ]]; then
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') 室内撮影完了、明るさ取得失敗" >> "$CRONLOG"
fi
