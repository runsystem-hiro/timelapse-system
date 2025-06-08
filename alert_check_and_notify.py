#!/usr/bin/env python3
import os
import csv
from datetime import datetime, timedelta
from dotenv import load_dotenv
from slack_notifier import SlackNotifier

# ログ関数


def log(msg):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}")


# .env の読み込み
load_dotenv("/home/pi/timelapse-system/.env")
SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
SLACK_DM_EMAIL = os.getenv("SLACK_DM_EMAIL")

CSV_PATH = f"/home/pi/timelapse-system/log/brightness_{datetime.now():%Y-%m}.csv"
ALERT_TIMESTAMP_FILE = "/home/pi/timelapse-system/log/last_alert_time"
ALERT_COOLDOWN_MINUTES = 30

# Slack通知クラス初期化
if SLACK_BOT_TOKEN is None:
    raise ValueError("環境変数 'SLACK_BOT_TOKEN' が未設定です。")
notifier = SlackNotifier(bot_token=SLACK_BOT_TOKEN, user_email=SLACK_DM_EMAIL)


def should_send_alert():
    if not os.path.exists(ALERT_TIMESTAMP_FILE):
        return True
    try:
        with open(ALERT_TIMESTAMP_FILE, "r") as f:
            last_time_str = f.read().strip()
            last_time = datetime.strptime(last_time_str, "%Y-%m-%d %H:%M:%S")
            return datetime.now() - last_time > timedelta(minutes=ALERT_COOLDOWN_MINUTES)
    except Exception:
        return True


def update_last_alert_time():
    with open(ALERT_TIMESTAMP_FILE, "w") as f:
        f.write(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))


def parse_latest_csv_entry():
    if not os.path.exists(CSV_PATH):
        return None, None, None
    with open(CSV_PATH, "r") as f:
        rows = list(csv.reader(f))
        for row in reversed(rows):
            if len(row) >= 8:
                return row[0], row[6], row[7]
    return None, None, None


def send_brightness_alert(timestamp, mean_str, filepath):
    try:
        mean_value = float(mean_str)
        if mean_value < 0.07:
            status = "暗すぎ"
        elif mean_value > 0.60:
            status = "明るすぎ"
        else:
            log("🔍 明るさは正常範囲内のため通知しません")
            return
    except ValueError:
        status = "明るさ取得失敗"

    comment = f"📛 明るさ異常検出: `{mean_str}`（{status}）\n🕒 {timestamp}"
    success = notifier.send_file(
        filepath=filepath,
        title="異常時撮影画像",
        comment=comment
    )
    if success:
        update_last_alert_time()
        log("✅ アラート送信完了")
    else:
        log("⚠️ アラート送信失敗")


if __name__ == "__main__":
    if not should_send_alert():
        log("⏳ クールタイム中のため、アラート送信をスキップ")
        exit(0)

    timestamp, filepath, mean_str = parse_latest_csv_entry()
    if not timestamp or not filepath or not mean_str:
        log("⚠️ CSVログの読み取りに失敗")
        exit(1)

    send_brightness_alert(timestamp, mean_str, filepath)
