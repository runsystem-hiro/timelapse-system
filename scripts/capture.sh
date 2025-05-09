#!/usr/bin/env bash
set -euo pipefail

ROTATION=0
VFLIP=false
HFLIP=false
FOCUS_POS=0.3

HDR_OPT=""
EV_OPT=""
SHUTTER_OPT=""
GAIN_OPT=""
METER_OPT=""
AWB_OPT="--awb fluorescent"
DENOISE_OPT="--denoise cdn_off"
ROT_OPT=""
AUTO_MODE=false

IMG_DIR="/home/pi/timelapse-system/images"
LOGFILE="/home/pi/timelapse-system/log/brightness.csv"
CRONLOG="/home/pi/timelapse-system/log/cron.log"
mkdir -p "$IMG_DIR"

STAMP=$(date +"%Y%m%d_%H%M%S")
OUTFILE="${IMG_DIR}/${STAMP}.jpg"
TMPFILE="/tmp/meancheck.jpg"

echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 室内撮影処理開始" >> "$CRONLOG"

HOUR=$(date +"%H")
HOUR=$((10#$HOUR))  # 先頭ゼロを含む値を明示的に10進数に変換

IS_EARLY_MORNING=false
IS_MORNING=false
IS_MIDDAY=false
IS_AFTERNOON=false
IS_EVENING=false
IS_NIGHT=false

[[ $HOUR -ge 4 && $HOUR -le 5 ]] && IS_EARLY_MORNING=true
[[ $HOUR -ge 6 && $HOUR -le 9 ]] && IS_MORNING=true
[[ $HOUR -ge 10 && $HOUR -le 13 ]] && IS_MIDDAY=true
[[ $HOUR -ge 14 && $HOUR -le 17 ]] && IS_AFTERNOON=true
[[ $HOUR -ge 18 && $HOUR -le 21 ]] && IS_EVENING=true
([[ $HOUR -ge 22 ]] || [[ $HOUR -le 3 ]]) && IS_NIGHT=true

clip_ev() {
  local ev="$1"
  awk -v ev="$ev" 'BEGIN {
    min = -6.0; max = 4.0;
    print (ev < min) ? min : (ev > max) ? max : ev
  }'
}

[[ $ROTATION != 0 ]] && ROT_OPT+=" --rotation $ROTATION"
[[ $VFLIP == true ]] && ROT_OPT+=" --vflip"
[[ $HFLIP == true ]] && ROT_OPT+=" --hflip"

# 仮撮影で mean 測定
libcamera-jpeg --nopreview --width 640 --height 360 --quality 50   $AWB_OPT $DENOISE_OPT   --lens-position "$FOCUS_POS"   -o "$TMPFILE" > /dev/null 2>&1 || true

MEAN=$(identify -format "%[fx:mean]" "$TMPFILE" 2>/dev/null || echo "n/a")
rm -f "$TMPFILE"

if [[ "$MEAN" != "n/a" ]]; then
  if (( $(echo "$MEAN < 0.15" | bc -l) )); then
    AUTO_MODE=true
    EV_OPT="--ev 0"
    METER_OPT="--metering centre"
  else
    AUTO_MODE=false
    SHUTTER_OPT="--shutter 10000"
    GAIN_OPT="--gain 3.0"
    METER_OPT="--metering centre"
  fi
else
  AUTO_MODE=true
  EV_OPT="--ev 0"
  METER_OPT="--metering centre"
fi

START_TIME=$(date +%s.%N)

if $AUTO_MODE; then
  libcamera-jpeg --nopreview --width 2304 --height 1296 --quality 90     $AWB_OPT $EV_OPT $METER_OPT $DENOISE_OPT     --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE"
else
  libcamera-jpeg --nopreview --width 2304 --height 1296 --quality 90     $AWB_OPT $METER_OPT $DENOISE_OPT     $SHUTTER_OPT $GAIN_OPT     --lens-position "$FOCUS_POS" $ROT_OPT -o "$OUTFILE"
fi

END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
echo "撮影時間: ${ELAPSED}秒"

MEAN_FINAL=$(identify -format "%[fx:mean]" "$OUTFILE" 2>/dev/null || echo "n/a")

MODE_STR="auto"
[[ $AUTO_MODE == false ]] && MODE_STR="manual"

TIME_INFO=""
[[ $IS_EARLY_MORNING == true ]] && TIME_INFO="early_morning"
[[ $IS_MORNING == true ]] && TIME_INFO="morning"
[[ $IS_MIDDAY == true ]] && TIME_INFO="midday"
[[ $IS_AFTERNOON == true ]] && TIME_INFO="afternoon"
[[ $IS_EVENING == true ]] && TIME_INFO="evening"
[[ $IS_NIGHT == true ]] && TIME_INFO="night"

if $AUTO_MODE; then
  echo "$(date '+%Y-%m-%d %H:%M:%S'),indoor,$MODE_STR,$TIME_INFO,auto,auto,$OUTFILE,$MEAN_FINAL,${EV_OPT#--ev }" >> "$LOGFILE"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S'),indoor,$MODE_STR,$TIME_INFO,${SHUTTER_OPT#--shutter },${GAIN_OPT#--gain },$OUTFILE,$MEAN_FINAL,n/a" >> "$LOGFILE"
fi

if [[ "$MEAN_FINAL" != "n/a" ]]; then
  echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 室内撮影完了、明るさ: $MEAN_FINAL" >> "$CRONLOG"
else
  echo "[LOG] $(date '+%Y-%m-%d %H:%M:%S') 室内撮影完了、明るさ取得失敗" >> "$CRONLOG"
fi
