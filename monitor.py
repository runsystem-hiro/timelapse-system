#!/usr/bin/env python3
"""
monitor.py — Timelapse‑system Monitoring & Daily Summary (Slack Bot 対応版)
"""

import os, sys, csv, time, argparse, logging, pathlib, shutil, subprocess, datetime
from dataclasses import dataclass
from typing import List, Optional

import psutil
from dotenv import load_dotenv
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

ROOT = pathlib.Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

SLACK_BOT_TOKEN  = os.getenv("SLACK_BOT_TOKEN")
SLACK_DM_EMAIL   = os.getenv("SLACK_DM_EMAIL")
DISK_THRESHOLD   = float(os.getenv("DISK_THRESHOLD", 80.0))
TEMP_THRESHOLD   = float(os.getenv("TEMP_THRESHOLD", 65.0))
SUPPRESS_MIN     = int(os.getenv("SUPPRESS_MIN", 30))
LOAD_THRESHOLD   = float(os.getenv("LOAD_THRESHOLD", 2.0))
MEM_THRESHOLD    = float(os.getenv("MEM_THRESHOLD", 80.0))

DISK_PATHS = {
    "images"  : "/home/pi/timelapse-system/images",
    "archived": "/home/pi/timelapse-system/archived",
}
PARTITION_ROOT = "/home/pi"
CSV_PATH       = ROOT / "log" / "system_log.csv"
SUPPRESS_FILE  = ROOT / "log" / "last_alert"

client = WebClient(token=SLACK_BOT_TOKEN)

def get_dm_channel():
    user_info = client.users_lookupByEmail(email=SLACK_DM_EMAIL)
    user_id = user_info["user"]["id"]
    conv = client.conversations_open(users=user_id)
    return conv["channel"]["id"]

def send_dm_message(text: str):
    try:
        channel_id = get_dm_channel()
        client.chat_postMessage(channel=channel_id, text=text)
    except SlackApiError as e:
        print(f"[Slack Error] {e.response['error']}")

LOG_PATH = ROOT / "log" / "monitor.log"
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_PATH), logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

def dir_size_kb(path: str) -> int:
    try:
        out = subprocess.check_output(["du","-s","--block-size=1K",path], text=True)
        return int(out.split()[0])
    except Exception as e:
        logger.error("dir_size_kb失敗 %s: %s", path, e)
        return 0

def cpu_temp_c() -> float:
    try:
        return psutil.sensors_temperatures()['cpu_thermal'][0].current
    except Exception:
        t = pathlib.Path("/sys/class/thermal/thermal_zone0/temp")
        return int(t.read_text())/1000 if t.exists() else float("nan")

@dataclass
class DiskMetric:
    label: str
    used_kb: int
    pct: float

def suppressed() -> bool:
    return SUPPRESS_FILE.exists() and (time.time()-int(SUPPRESS_FILE.read_text()))<SUPPRESS_MIN*60

def mark_alert(): SUPPRESS_FILE.write_text(str(int(time.time())))

def run_monitor(no_slack=False, ignore_suppress=False, force_alert=False):
    ts = time.strftime("%Y-%m-%d %H:%M")
    logger.info("監視開始 %s", ts)

    total_kb = shutil.disk_usage(PARTITION_ROOT).total // 1024
    metrics: List[DiskMetric] = [
        DiskMetric(lbl, dir_size_kb(p), dir_size_kb(p)/total_kb*100)
        for lbl,p in DISK_PATHS.items()]

    temp_c  = cpu_temp_c()
    load1   = os.getloadavg()[0]
    mem_pct = psutil.virtual_memory().percent

    img_files = subprocess.check_output(["find", DISK_PATHS["archived"], "-type","f","-name","*.jpg","-printf","%T@\n"],text=True)
    imgs = [float(x) for x in img_files.splitlines()] if img_files else []
    new_img = sum(1 for t_ in imgs if time.time()-t_ < 3600)
    img_cnt = len(imgs)

    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("a", newline="") as f:
        csv.writer(f).writerow([
            ts, metrics[0].used_kb, metrics[1].used_kb,
            f"{metrics[0].pct:.1f}", f"{metrics[1].pct:.1f}", f"{temp_c:.1f}",
            new_img, img_cnt, f"{load1:.2f}", f"{mem_pct:.1f}"
        ])

    alerts = []
    if force_alert:
        alerts.append("🧪 強制テストアラート (--force-alert)")

    for m in metrics:
        if m.pct >= DISK_THRESHOLD:
            alerts.append(f"💾 {m.label} {m.pct:.1f}% (≧{DISK_THRESHOLD}%)")
    if temp_c >= TEMP_THRESHOLD:
        alerts.append(f"🌡️ CPU {temp_c:.1f}℃ (≧{TEMP_THRESHOLD}℃)")
    if load1 >= LOAD_THRESHOLD:
        alerts.append(f"📈 LoadAvg {load1:.2f} (≧{LOAD_THRESHOLD})")
    if mem_pct >= MEM_THRESHOLD:
        alerts.append(f"💽 Mem {mem_pct:.1f}% (≧{MEM_THRESHOLD}%)")

    if alerts and (ignore_suppress or not suppressed()) and not no_slack:
        host = pathlib.Path("/etc/hostname").read_text().strip()
        send_dm_message(f"🚨 *{host}*\n" + "\n".join(alerts))
        mark_alert()
    logger.info("監視終了")

def run_daily_summary(date: Optional[datetime.date] = None, no_slack=False):
    if date is None:
        date = datetime.date.today()-datetime.timedelta(days=1)
    dstr = date.strftime("%Y-%m-%d")
    rows: list[list[str]] = []
    if not CSV_PATH.exists():
        logger.warning("CSVなし")
        return
    with CSV_PATH.open() as f:
        for r in csv.reader(f):
            if r and r[0].startswith(dstr):
                rows.append(r+['0']*10)
    if not rows:
        logger.warning("対象日データなし %s", dstr)
        return

    idx = lambda n, default=0.0: [float(r[n]) for r in rows if len(r)>n]

    img_max = max(idx(3))
    arc_max = max(idx(4))
    temp_avg= sum(idx(5))/len(rows)
    temp_max= max(idx(5))
    new_total= int(sum(idx(6)))

    log_kb = dir_size_kb(ROOT/"log")

    lines = [f"📊 *{dstr}* サマリ",
             f"🖼️ images 最大 : {img_max:.1f}%  / 💾 archived 最大 : {arc_max:.1f}%",
             f"🌡️ CPU 平均 {temp_avg:.1f}℃ / 最大 {temp_max:.1f}℃",
             f"📷 撮影枚数     : {new_total} 枚",
             f"📝 log ディレクトリ : {log_kb/1024:.1f} MB"]

    if not no_slack:
        send_dm_message("\n".join(lines))
    logger.info("日次サマリ送信完了")

def parse_args():
    p = argparse.ArgumentParser(description="timelapse-system monitor")
    p.add_argument("--once", action="store_true")
    p.add_argument("--no-slack", action="store_true")
    p.add_argument("--daily", action="store_true")
    p.add_argument("--date")
    p.add_argument("--force-alert", action="store_true")
    return p.parse_args()

def main():
    a=parse_args()
    if a.daily:
        tgt=None
        if a.date:
            tgt=datetime.datetime.strptime(a.date,"%Y-%m-%d").date()
        run_daily_summary(tgt, a.no_slack)
    else:
        run_monitor(a.no_slack, a.once, a.force_alert)

if __name__=="__main__":
    main()
