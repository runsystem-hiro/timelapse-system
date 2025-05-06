#!/usr/bin/env python3
import os
import subprocess
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from dotenv import load_dotenv
from datetime import datetime
import csv

# .envの読み込み
load_dotenv()
SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
DM_USER_EMAIL = os.getenv("SLACK_DM_EMAIL")

CSV_PATH = "/home/pi/timelapse-system/log/brightness.csv"
PLOT_SCRIPT = "/home/pi/timelapse-system/plot_mean.py"
PLOT_IMAGE = "/home/pi/timelapse-system/log/brightness_plot.png"

client = WebClient(token=SLACK_BOT_TOKEN)

def run_plot_script():
    subprocess.run(["python3", PLOT_SCRIPT], check=True)

def analyze_trend():
    means = []
    try:
        with open(CSV_PATH, "r") as f:
            rows = list(csv.reader(f))
            for row in rows[-10:]:
                try:
                    means.append(float(row[7]))
                except:
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
    print("Slackに画像とレポートを送信中...")

    try:
        # グラフ生成
        run_plot_script()

        # DM先ユーザーID取得
        user_info = client.users_lookupByEmail(email=DM_USER_EMAIL)
        user_id = user_info["user"]["id"]
        conv = client.conversations_open(users=user_id)
        channel_id = conv["channel"]["id"]

        # 平均明るさと傾向取得
        latest_mean = "n/a"
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(CSV_PATH, "r") as f:
            lines = f.readlines()
            if lines:
                last = lines[-1].strip().split(",")
                latest_mean = last[7]
        trend_summary = analyze_trend()

        # メッセージ装飾
        comment = (
            f"📡 *タイムラプスレポート*\n"
            f"> 🕒 {timestamp}\n"
            f"> 💡 平均明るさ: `{latest_mean}`\n"
            f"> 📊 傾向: {trend_summary}"
        )

        # 明るさ推移グラフ送信
        client.files_upload_v2(
            channel=channel_id,
            file=PLOT_IMAGE,
            title="明るさ推移グラフ",
            filename="brightness_plot.png",
            initial_comment=comment,
        )

        # 最新画像送信
        latest_img = get_latest_image_path()
        if latest_img and os.path.exists(latest_img):
            client.files_upload_v2(
                channel=channel_id,
                file=latest_img,
                title="最新撮影画像",
                filename=os.path.basename(latest_img),
                initial_comment="📸最新の代表画像です。",
            )

        print("✅ Slack送信成功")

    except SlackApiError as e:
        print(f"[エラー] Slack送信失敗: {e.response['error']}")
    except Exception as e:
        print(f"[エラー] 処理中に例外発生: {e}")

if __name__ == "__main__":
    send_report()
