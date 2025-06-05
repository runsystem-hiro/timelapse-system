#!/usr/bin/env python3
import os
import subprocess
from datetime import datetime
import csv
from dotenv import load_dotenv
from slack_notifier import SlackNotifier

# ログ関数
def log(msg):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}")

# .envの読み込み
load_dotenv("/home/pi/timelapse-system/.env")
SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
SLACK_DM_EMAIL = os.getenv("SLACK_DM_EMAIL")

CSV_PATH = f"/home/pi/timelapse-system/log/brightness_{datetime.now():%Y-%m}.csv"
# PLOT_SCRIPT = "/home/pi/timelapse-system/plot_mean.py"
# PLOT_IMAGE = "/home/pi/timelapse-system/log/brightness_plot.png"

notifier = SlackNotifier(bot_token=SLACK_BOT_TOKEN, user_email=SLACK_DM_EMAIL)

# def run_plot_script():
#     subprocess.run(["python3", PLOT_SCRIPT], check=True)

def analyze_trend():
    means = []
    try:
        with open(CSV_PATH, "r") as f:
            rows = list(csv.reader(f))
            for row in rows[-10:]:
                try:
                    means.append(float(row[7]))
                except ValueError:
                    continue
        if len(means) < 2:
            return "データが不十分です。"

        delta = means[-1] - means[0]
        if delta > 0.05:
            return "📈 明るさが上昇傾向です"
        elif delta < -0.05:
            return "📉 明るさが下降傾向です"
        else:
            return "➖ 明るさは安定しています"
    except Exception as e:
        return f"解析失敗: {e}"

def get_latest_image_path():
    try:
        with open(CSV_PATH, "r") as f:
            lines = f.readlines()
            if lines:
                last = lines[-1].strip().split(",")
                if len(last) >= 7:
                    return last[6]
    except:
        return None
    return None

def send_report():
    log("📤 Slackにタイムラプスレポートを送信中...")

    try:
        # # グラフ生成
        # run_plot_script()

        # 最新データ
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        latest_mean = "n/a"
        with open(CSV_PATH, "r") as f:
            lines = f.readlines()
            if lines:
                last = lines[-1].strip().split(",")
                latest_mean = last[7]
        trend_summary = analyze_trend()

        # コメント文生成
        comment = (
            f"📡 *タイムラプスレポート*\n"
            f"> 🕒 {timestamp}\n"
            f"> 💡 平均明るさ: `{latest_mean}`\n"
            f"> 📊 傾向: {trend_summary}"
        )

        # # グラフ送信
        # graph_success = notifier.send_file(
        #     filepath=PLOT_IMAGE,
        #     title="明るさ推移グラフ",
        #     comment=comment
        # )

        # 最新画像送信
        latest_img = get_latest_image_path()
        image_success = False
        if latest_img and os.path.exists(latest_img):
            image_success = notifier.send_file(
                filepath=latest_img,
                title="最新撮影画像",
                comment=comment
            )

        # if graph_success or image_success:
        if image_success:
            log("✅ レポート送信完了")
        else:
            log("⚠️ レポート送信に失敗")

    except Exception as e:
        log(f"[エラー] レポート送信中に例外発生: {e}")

if __name__ == "__main__":
    send_report()
