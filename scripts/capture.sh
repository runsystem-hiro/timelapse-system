#!/usr/bin/env bash
#=========================================================
#  timelapse-system : Capture Script 〈Indoor / Outdoor 切替版〉
#=========================================================
#  Raspberry Pi Camera Module V3 / libcamera-jpeg 専用
#  使い方:
#      ./capture.sh           # → outdoor モード（既定）
#      ./capture.sh indoor    # → 室内蛍光灯モード
#      ./capture.sh outdoor   # → 屋外ランドスケープモード
#---------------------------------------------------------
#  indoor  : 蛍光灯 (50 Hz) 下で適正露出。フリッカー抑制 & AWB 固定。
#            消灯時も AE が追随できるよう EV +0.2・HDR 無効でノイズHQ。
#  outdoor : 自動露出 + HDR(+1EV) で逆光と夜景をカバー。AWB auto。
#=========================================================
set -euo pipefail

##############################
# ▼共通ユーザー設定
ROTATION=180        # 0 / 90 / 180 / 270
VFLIP=false       # true = 上下反転
HFLIP=false       # true = 左右反転
IMG_DIR="/home/pi/timelapse-system/images"
mkdir -p "$IMG_DIR"
##############################

MODE="${1:-outdoor}"   # 引数がなければ outdoor
STAMP=$(date +"%Y%m%d_%H%M%S")
OUTFILE="${IMG_DIR}/${STAMP}.jpg"

##############################
# ▼モード別パラメータ
case "$MODE" in
  indoor)
    FOCUS_POS=2.0                     # 室内 2〜5 m
    FLICKER_OPT="--flicker 50hz"
    AWB_OPT="--awb fluorescent"
    HDR_OPT=""                       # HDR off
    EV_OPT="--ev 0.2"
    METER_OPT="--metering centre"
    DENOISE_OPT="--denoise cdn_hq"
    ;;
  outdoor)
    FOCUS_POS=0.0                     # 無限遠
    FLICKER_OPT=""                   # 屋外なので不要
    AWB_OPT="--awb auto"
    HDR_OPT="--hdr 1"                # 2‑frame HDR
    EV_OPT="--ev 0.3"
    METER_OPT="--metering centre"
    DENOISE_OPT="--denoise cdn_hq"
    ;;
  *)
    echo "[ERROR] unknown mode: $MODE (use indoor|outdoor)" >&2
    exit 1
    ;;
esac
##############################

# ▼回転・反転オプション
ROT_OPT=""
[[ $ROTATION != 0 ]] && ROT_OPT+=" --rotation $ROTATION"
[[ $VFLIP == true ]] && ROT_OPT+=" --vflip"
[[ $HFLIP == true ]] && ROT_OPT+=" --hflip"

# ▼撮影実行
libcamera-jpeg \
  --nopreview \
  --width 2304 --height 1296 \
  --quality 90 \
  $HDR_OPT \
  $FLICKER_OPT \
  $AWB_OPT \
  $EV_OPT \
  $METER_OPT \
  $DENOISE_OPT \
  --lens-position "$FOCUS_POS" \
  $ROT_OPT \
  -o "$OUTFILE"

# ▼平均輝度を取得（ImageMagick が入っていれば）
MEAN=$(identify -format "%[fx:mean]" "$OUTFILE" 2>/dev/null || echo "n/a")

# ▼ログ
echo "[ $(date '+%F %T') ] mode=$MODE ${OUTFILE} mean=${MEAN}" \
     >> /home/pi/timelapse-system/log/capture.log
