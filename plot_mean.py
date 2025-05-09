#!/usr/bin/env python3
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import pandas as pd
import numpy as np
from datetime import datetime

# ===== 設定 =====
CSV_PATH = "/home/pi/timelapse-system/log/brightness.csv"
PLOT_PATH = "/home/pi/timelapse-system/log/brightness_plot.png"

# 明るさの閾値
TARGET_MIN = 0.25
TARGET_MAX = 0.35
TOO_BRIGHT = 0.40

# 夜間帯の時間
NIGHT_START_HOUR = 0
NIGHT_END_HOUR = 6

# 手動X軸範囲（Noneなら自動）
CUSTOM_XLIM_START = None  # datetime(2025, 5, 4, 14, 0)
CUSTOM_XLIM_END   = None  # datetime(2025, 5, 5, 12, 0)

# ===== CSV 読み込み =====
df = pd.read_csv(CSV_PATH, header=None, names=[
    "timestamp", "mode", "mode_str", "time_info", "shutter", "gain", "path", "mean", "ev"
])
df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")
df["mean"] = pd.to_numeric(df["mean"], errors="coerce")
df["ev"] = pd.to_numeric(df["ev"], errors="coerce")

auto_df = df[df["mode_str"] == "auto"]
manual_df = df[df["mode_str"] == "manual"]

# ===== プロット作成 =====
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 9), sharex=False, gridspec_kw={"height_ratios": [3, 1]})

# ===== 上：時系列の明るさ =====
ax1.axhspan(TARGET_MIN, TARGET_MAX, color="yellow", alpha=0.2, label="Target Range (0.18~0.25)")
ax1.axhline(TARGET_MIN, color="green", linestyle="--", label="Target Min (0.18)")
ax1.axhline(TARGET_MAX, color="orange", linestyle="--", label="Target Max (0.25)")
ax1.axhline(TOO_BRIGHT, color="red", linestyle="--", label="Too Bright (0.35)")

auto_sizes = np.clip((abs(auto_df["ev"].fillna(0)) + 1) * 20, 10, 100)
manual_sizes = np.full(len(manual_df), 20)

ax1.scatter(auto_df["timestamp"], auto_df["mean"], color="blue", s=auto_sizes, label="Auto Mode")
ax1.scatter(manual_df["timestamp"], manual_df["mean"], color="green", s=manual_sizes, label="Manual Mode")

# 夜間帯の背景
unique_dates = df["timestamp"].dt.normalize().unique()
for date in unique_dates:
    night_start = date + pd.Timedelta(hours=NIGHT_START_HOUR)
    night_end = date + pd.Timedelta(hours=NIGHT_END_HOUR)
    ax1.axvspan(night_start, night_end, color="gray", alpha=0.15)

ax1.set_ylabel("Mean Brightness")
ax1.set_title("Brightness Over Time and Histogram")
ax1.legend()
ax1.grid(True)
ax1.xaxis.set_major_formatter(mdates.DateFormatter('%m-%d %H:%M'))
plt.setp(ax1.get_xticklabels(), rotation=45)

# ===== 下：ヒストグラム =====
ax2.hist(df["mean"].dropna(), bins=30, color="purple", alpha=0.7, edgecolor="black")
ax2.axvline(TARGET_MIN, color="green", linestyle="--", label="Target Min (0.18)")
ax2.axvline(TARGET_MAX, color="orange", linestyle="--", label="Target Max (0.25)")
ax2.axvline(TOO_BRIGHT, color="red", linestyle="--", label="Too Bright (0.35)")
ax2.set_xlabel("Mean Brightness")
ax2.set_ylabel("Frequency")
ax2.grid(True)
ax2.legend()

# ===== X軸範囲の設定 =====
if CUSTOM_XLIM_START is not None and CUSTOM_XLIM_END is not None:
    ax1.set_xlim(CUSTOM_XLIM_START, CUSTOM_XLIM_END)
else:
    ax1.set_xlim(df["timestamp"].min(), df["timestamp"].max())

plt.tight_layout()
plt.savefig(PLOT_PATH)
print(f"Saved plot to: {PLOT_PATH}")
