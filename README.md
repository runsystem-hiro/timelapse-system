# timelapse-system

## 概要

`timelapse-system` は、Raspberry Pi Zero 2 W と Camera Module v3 を用いて、24×365 のタイムラプス撮影を自動化・安定運用するためのフルスタックソリューションです。  
撮影 → ローカル・NAS への同期 → MJPEG ライブ配信 → リソース監視・Slack 通知 → 日次サマリ の一連ワークフローをスクリプトと systemd/timer、cron でシームレスに実現します。

## 特徴

- 📸 **屋内外対応の明るさ制御付き撮影**（`scripts/capture.sh`, `scripts/capture_outdoor.sh`）
- 🧠 **明るさに基づく撮影モード自動切替（AUTO/MANUAL）**
- 💾 **ローカル→NASへの画像同期**
- 🌐 **MJPEGによるライブビュー配信**
- 📊 **明るさトレンドグラフ生成**
- 🔔 **明るさ異常時のSlack通知**
- 📈 **ディスク・温度・負荷のリソース監視＋アラート**
- 📨 **Slack DMで日次サマリを定時送信**

## 前提条件

1. **ハードウェア**
   - Raspberry Pi Zero 2 W（Wi-Fi 接続済み）
   - Camera Module v3 (IMX708)
   - microSD カード（16 GB 以上推奨）
2. **ソフトウェア**
   - OS：Raspberry Pi OS Lite (Bullseye)
   - libcamera-apps (`rpicam-still`, `rpicam-vid`)
   - Bash、Python3
   - 必須パッケージ：`rsync`, `imagemagick`, `python3-psutil`, `python3-dotenv`, `slack_sdk`, `pandas`, `matplotlib`, `requests`

## ディレクトリ構成

```bash
timelapse-system/
├── .env.example                   # 環境変数テンプレート
├── scripts/
│   ├── capture.sh                # 室内専用：明るさ制御付き撮影スクリプト（デフォルト）
│   ├── capture_outdoor.sh        # 屋外室内両対応：明るさ制御付き撮影スクリプト（任意）
│   ├── sync_local.sh             # images → archived 同期（5分間隔）
│   └── sync_to_nas.sh            # archived → NAS 同期 & 古い画像削除（毎日）
├── mjpeg_server.py               # MJPEGライブビュー配信サーバ
├── alert_check_and_notify.py     # 明るさ異常検出＆Slack通知
├── monitor.py                    # リソース監視と日次レポート送信
├── plot_mean.py                  # 明るさグラフ生成
├── send_report_to_slack.py       # グラフ付きレポート送信
├── images/                       # 撮影画像の保存先（cronで生成）
├── archived/                     # アーカイブ済み画像（NAS同期対象）
└── log/
    ├── brightness.csv            # 撮影ログ（mean/露出など）
    ├── capture.log               # 撮影ログ
    ├── monitor.log               # 監視ログ
    ├── sync_nas.log              # NAS同期ログ
    ├── brightness_plot.png       # 明るさ推移グラフ
    └── last_alert_time           # アラート送信抑制のタイムスタンプ
```

## インストール手順

```bash
git clone https://github.com/runsystem-hiro/timelapse-system.git
cd timelapse-system

sudo apt update
sudo apt install -y rsync imagemagick libcamera-apps python3-psutil
pip3 install python-dotenv slack_sdk pandas matplotlib requests

cp .env.example .env  # 内容を自環境に応じて編集
```

## `.env` 設定例

```dotenv
DISK_THRESHOLD=70.0
TEMP_THRESHOLD=65.0
SUPPRESS_MIN=30
LOAD_THRESHOLD=2.0
MEM_THRESHOLD=80.0
LOG_ROTATE_DAYS=30
NAS_DEST="rsync://yournas"
SLACK_BOT_TOKEN=xoxb-
SLACK_DM_EMAIL=your@email.com
```

## スケジューリング設定例

### `crontab`（撮影・同期・通知）

```cron
# 毎分撮影（デフォルトは室内専用）
* * * * * /home/pi/timelapse-system/scripts/capture.sh >> /home/pi/timelapse-system/log/cron.log 2>&1

# 毎分撮影（屋外室内両対応モード）※必要時に有効化
#* * * * * /home/pi/timelapse-system/scripts/capture_outdoor.sh  >> /home/pi/timelapse-system/log/cron.log 2>&1

# 撮影から1分空けて、2分以降 5分おきにローカル同期（images → archived）
2-59/5 * * * * /home/pi/timelapse-system/scripts/sync_local.sh >/dev/null 2>&1

# 毎日 2:00 に NAS へ同期し、50日超の jpg を削除（同期成功時のみ）
0 2 * * * /home/pi/timelapse-system/scripts/sync_to_nas.sh

# 毎日 23:55 に mjpeg_server.py を終了（ストリーム消し忘れ対策）
55 23 * * * pkill -f mjpeg_server.py

# 明るさ異常の監視・通知（15分おき）
*/15 * * * * /usr/bin/python3 /home/pi/timelapse-system/alert_check_and_notify.py >> /home/pi/timelapse-system/log/cron.log 2>&1

# 明るさレポートを Slack に送信（毎日 0時30分、6時、9時、12時、15時、18時、21時）
30 0,6,9,12,15,18,21 * * * /usr/bin/python3 /home/pi/timelapse-system/send_report_to_slack.py >> /home/pi/timelapse-system/log/cron.log 2>&1
```

### `systemd-timer` 設定例

#### `/etc/systemd/system/monitor.service`

```ini
[Unit]
Description=Timelapse System Monitor

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/pi/timelapse-system/monitor.py
WorkingDirectory=/home/pi/timelapse-system
EnvironmentFile=/home/pi/timelapse-system/.env
Restart=on-failure
```

#### `/etc/systemd/system/monitor.timer`

```ini
[Unit]
Description=Run Timelapse System Monitor Hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

#### 有効化コマンド

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now monitor.timer
```

## 使用例

### MJPEGライブ配信（http://<PiのIP>:8000）

```bash
python3 mjpeg_server.py
```

ブラウザで `http://<RPI_IP>:8080` にアクセスしてください。

### 明るさグラフ付きSlackレポートを即時送信

```bash
python3 send_report_to_slack.py
```

### 任意日の日次サマリを送信

```bash
python3 monitor.py --daily --date 2025-05-01
```

---
