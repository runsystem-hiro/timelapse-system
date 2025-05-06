#!/usr/bin/env python3
import os
import csv
import time
from datetime import datetime, timedelta
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from dotenv import load_dotenv

# .env 読み込み
load_dotenv("/home/pi/timelapse-system/.env")
SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
SLACK_DM_EMAIL = os.getenv("SLACK_DM_EMAIL")

CSV_PATH = "/home/pi/timelapse-system/log/brightness.csv"
ALERT_TIMESTAMP_FILE = "/home/pi/timelapse-system/log/last_alert_time.txt"
ALERT_COOLDOWN_MINUTES = 30

client = WebClient(token=SLACK_BOT_TOKEN)

def get_dm_channel_id():
    response = client.users_lookupByEmail(email=SLACK_DM_EMAIL)
    return response["user"]["id"]

def should_send_alert():
    if not os.path.exists(ALERT_TIMESTAMP_FILE):
        return True
    with open(ALERT_TIMESTAMP_FILE, "r") as f:
        last_time_str = f.read().strip()
        try:
            last_time = datetime.strptime(last_time_str, "%Y-%m-%d %H:%M:%S")
            return datetime.now() - last_time > timedelta(minutes=ALERT_COOLDOWN_MINUTES)
        except ValueError:
            return True

def update_last_alert_time():
    with open(ALERT_TIMESTAMP_FILE, "w") as f:
        f.write(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

def parse_latest_csv_entry():
    with open(CSV_PATH, "r") as f:
        rows = list(csv.reader(f))
        for row in reversed(rows):
            if len(row) >= 8:
                timestamp = row[0]
                filepath = row[6]
                mean_str = row[7]
                return timestamp, filepath, mean_str
    return None, None, None

def send_alert(channel_id, timestamp, mean_str, filepath):
    try:
        mean_value = float(mean_str)
        if mean_value < 0.07:
            status = "暗すぎ"
        elif mean_value > 0.60:
            status = "明るすぎ"
        else:
            return  # 通常範囲内なら何もしない
    except ValueError:
        status = "明るさ取得失敗"

    comment = f"📛 明るさ異常検出: `{mean_str}`（{status}）\n🕒 {timestamp}"
    client.files_upload_v2(
        channel=channel_id,
        file=filepath,
        title="異常時撮影画像",
        filename=os.path.basename(filepath),
        initial_comment=comment
    )
    update_last_alert_time()
    print("✅ アラート送信完了")

if __name__ == "__main__":
    if not should_send_alert():
        print("⏳ クールタイム中のため、アラート送信をスキップ")
        exit(0)

    timestamp, filepath, mean_str = parse_latest_csv_entry()
    if not timestamp or not filepath or not mean_str:
        print("⚠️ CSVログの読み取りに失敗")
        exit(1)

    user_id = get_dm_channel_id()
    send_alert(user_id, timestamp, mean_str, filepath)
