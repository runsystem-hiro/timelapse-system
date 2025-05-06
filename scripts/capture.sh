#!/usr/bin/env bash
set -euo pipefail

# 設定
ROTATION=180
VFLIP=false
HFLIP=false
FOCUS_POS=1.0

HDR_OPT=""
EV_OPT=""
SHUTTER_OPT=""
GAIN_OPT=""
METER_OPT=""
FLICKER_OPT=""
AWB_OPT=""
DENOISE_OPT=""
ROT_OPT=""
AUTO_MODE=false
SKIP_TEST_SHOT=false

IMG_DIR="/home/pi/timelapse-system/images"
LOGFILE="/home/pi/timelapse-system/log/brightness.csv"
CRONLOG="/home/pi/timelapse-system/log/cron.log"
mkdir -p "$IMG_DIR"

MODE="${1:-outdoor}"
STAMP=$(date +"%Y%m%d_%H%M%S")
OUTFILE="${IMG_DIR}/${STAMP}.jpg"
TMPFILE="/tmp/meancheck.jpg"

echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 撮影処理開始" >> "$CRONLOG"

TARGET_MEAN_MIN=0.18
TARGET_MEAN_MAX=0.25
MAX_RETRIES=2

HOUR=$(date +"%H")
IS_DAYTIME=false
IS_MIDDAY=false
[[ $HOUR -ge 6 && $HOUR -le 18 ]] && IS_DAYTIME=true
[[ $HOUR -ge 10 && $HOUR -le 15 ]] && IS_MIDDAY=true

# EV 安全範囲クリップ
clip_ev() {
  local ev="$1"
  awk -v ev="$ev" 'BEGIN {
    min = -6.0; max = 4.0;
    print (ev < min) ? min : (ev > max) ? max : ev
  }'
}

# 回転設定
[[ $ROTATION != 0 ]] && ROT_OPT+=" --rotation $ROTATION"
[[ $VFLIP == true ]] && ROT_OPT+=" --vflip"
[[ $HFLIP == true ]] && ROT_OPT+=" --hflip"

# モード判定
case "$MODE" in
  indoor)
    FLICKER_OPT="--flicker 50hz"
    AWB_OPT="--awb fluorescent"
    ;;
  outdoor)
    FLICKER_OPT=""
    AWB_OPT="--awb auto"
    [[ $IS_DAYTIME == true ]] && HDR_OPT="--hdr"
    ;;
  *)
    echo "[ERROR] unknown mode: $MODE" >&2
    exit 1
    ;;
esac

DENOISE_OPT="--denoise cdn_off"

# 仮撮影で mean 測定
libcamera-jpeg --nopreview --width 640 --height 360 --quality 50 \
  $AWB_OPT $DENOISE_OPT $HDR_OPT \
  --lens-position "$FOCUS_POS" \
  -o "$TMPFILE" > /dev/null 2>&1 || true

MEAN=$(identify -format "%[fx:mean]" "$TMPFILE" 2>/dev/null || echo "n/a")
rm -f "$TMPFILE"

# 明るさに応じた初期設定
if [[ "$MEAN" != "n/a" ]]; then
  if (( $(echo "$MEAN > $TARGET_MEAN_MAX" | bc -l) )); then
    AUTO_MODE=true
    EV_OPT="--ev $(clip_ev -6.0)"
    METER_OPT="--metering spot"
  elif (( $(echo "$MEAN < $TARGET_MEAN_MIN" | bc -l) )); then
    AUTO_MODE=false
    SHUTTER_OPT="--shutter 1000000"
    GAIN_OPT="--gain 2.0"
    METER_OPT="--metering centre"
  else
    AUTO_MODE=false
    SHUTTER_OPT="--shutter 400000"
    GAIN_OPT="--gain 1.0"
    METER_OPT="--metering centre"
  fi
else
  AUTO_MODE=false
  SHUTTER_OPT="--shutter 400000"
  GAIN_OPT="--gain 1.0"
  METER_OPT="--metering centre"
fi

# 撮影ループ（リトライ対応）
RETRY_COUNT=0
while :; do
  START_TIME=$(date +%s.%N)

  if $AUTO_MODE; then
    libcamera-jpeg --nopreview --width 2304 --height 1296 --quality 90 \
      $HDR_OPT $FLICKER_OPT $AWB_OPT $EV_OPT $METER_OPT $DENOISE_OPT \
      --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE"
  else
    libcamera-jpeg --nopreview --width 2304 --height 1296 --quality 90 \
      $HDR_OPT $FLICKER_OPT $AWB_OPT $METER_OPT $DENOISE_OPT \
      $SHUTTER_OPT $GAIN_OPT \
      --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE"
  fi

  END_TIME=$(date +%s.%N)
  ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
  echo "撮影時間: ${ELAPSED}秒"

  MEAN_FINAL=$(identify -format "%[fx:mean]" "$OUTFILE" 2>/dev/null || echo "n/a")
  [[ "$MEAN_FINAL" == "n/a" ]] && break

  if (( $(echo "$MEAN_FINAL > 0.35" | bc -l) )) && (( RETRY_COUNT < MAX_RETRIES )); then
    echo "[WARN] 明るすぎるため再撮影 ($MEAN_FINAL)" | tee -a "$CRONLOG"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    EV_NOW=$(echo "$EV_OPT" | awk '{print $2}')
    EV_NEXT=$(clip_ev "$(echo "$EV_NOW - 1.0" | bc)")
    EV_OPT="--ev $EV_NEXT"
    continue
  fi
  break
done

# ログ出力
MODE_STR="auto"
[[ $AUTO_MODE == false ]] && MODE_STR="manual"

TIME_INFO=""
[[ $IS_MIDDAY == true ]] && TIME_INFO="midday"
[[ $IS_DAYTIME == true && $IS_MIDDAY == false ]] && TIME_INFO="daytime"
[[ $IS_DAYTIME == false ]] && TIME_INFO="night"

if $AUTO_MODE; then
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$MODE,$MODE_STR,$TIME_INFO,auto,auto,$OUTFILE,$MEAN_FINAL,${EV_OPT#--ev }" >> "$LOGFILE"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$MODE,$MODE_STR,$TIME_INFO,${SHUTTER_OPT#--shutter },${GAIN_OPT#--gain },$OUTFILE,$MEAN_FINAL,n/a" >> "$LOGFILE"
fi

if [[ "$MEAN_FINAL" != "n/a" ]]; then
  echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 撮影完了、明るさ: $MEAN_FINAL" >> "$CRONLOG"
else
  echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 撮影完了、明るさ取得失敗" >> "$CRONLOG"
fi
