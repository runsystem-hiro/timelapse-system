# timelapse-system

## 概要

`timelapse-system` は、Raspberry Pi Zero 2 W と Camera Module v3 を用いて、24×365 のタイムラプス撮影を自動化・安定運用するためのフルスタックソリューションです。  
撮影 → ローカル・NAS への同期 → MJPEG ライブ配信 → リソース監視・Slack 通知 → 日次サマリ の一連ワークフローをスクリプトと systemd/timer、cron でシームレスに実現します。

## 特徴

- **高頻度撮影**：60 秒～5 分間隔で静止画をキャプチャ  
- **多段階アーカイブ**：ローカル → NAS へ自動同期  
- **ライブビュー**：最新画像を MJPEG サーバで HTTP 配信  
- **リソース監視**：ディスク使用率・CPU 温度を定期収集し、しきい値超過時は Slack へ即時通知  
- **日次レポート**：前日分の集計を Slack DM で配信  
- **フル自動化**：cron／systemd-timer による運用

## 前提条件

1. **ハードウェア**
   - Raspberry Pi Zero 2 W（Wi-Fi 接続済み）
   - Camera Module v3 (IMX708)
   - microSD カード（16 GB 以上推奨）
2. **ソフトウェア**
   - OS：Raspberry Pi OS Lite (Bullseye)
   - libcamera-apps (`rpicam-still`, `rpicam-vid`)
   - Bash、Python3
   - rsync、systemd

## ディレクトリ構成

```bash
timelapse-system/
├── .env.example          # 設定テンプレート
├── images/               # 撮影直後の一時画像
├── archived/             # アーカイブ済み画像（NAS と同期）
├── scripts/
│   ├── capture.sh        # 撮影スクリプト（cron 制御）
│   ├── sync_local.sh     # ローカル同期スクリプト
│   └── sync_to_nas.sh    # NAS 同期スクリプト
├── monitor.py            # リソース監視＆通知
├── mjpeg_server.py       # MJPEG ライブ配信サーバ
└── log/
    ├── capture.log
    ├── system_log.csv    # 監視メトリクス蓄積用
    ├── monitor.log
    └── sync_nas.log
```

## インストール & 設定

1. リポジトリをクローン  

   ```bash
   git clone https://github.com/runsystem-hiro/timelapse-system.git
   cd timelapse-system
   ```

2. 依存パッケージをインストール  

   ```bash
   sudo apt update
   sudo apt install -y python3-psutil rsync
   pip3 install python-dotenv requests
   ```

3. 環境変数ファイルを作成  
   リポジトリルートの `.env.example` をコピーし、実運用向けに値を設定します。  

   ```bash
   cp .env.example .env
   ```

   **主な環境変数**（例）  

   ```dotenv
   GAS_WEBHOOK=YOUR_GAS_WEBHOOK_URL
   SLACK_USER_ID=YOUR_SLACK_USER_ID
   DISK_THRESHOLD=80
   TEMP_THRESHOLD=65
   SUPPRESS_MIN=30
   ```

## Cron／systemd 設定例

### cron（撮影 & 同期）

```cron
# 毎分撮影
* * * * * /home/pi/timelapse-system/scripts/capture.sh >> ~/timelapse-system/log/capture.log 2>&1
# 5分ごとにローカル同期
*/5 * * * * /home/pi/timelapse-system/scripts/sync_local.sh >/dev/null 2>&1
# 毎日 02:00 に NAS 同期＆古い画像削除
0 2 * * * /home/pi/timelapse-system/scripts/sync_to_nas.sh >> ~/timelapse-system/log/sync_nas.log 2>&1
```

### systemd-timer（監視系）

1. ユニットファイルを `/etc/systemd/system/` に配置  
   - `monitor.service` + `monitor.timer`（毎時実行）  
   - `monitor-daily.service` + `monitor-daily.timer`（日次 00:05 実行）
2. タイマーを有効化  

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now monitor.timer monitor-daily.timer
   ```

## 使い方

- **単発アラートのテスト**  

  ```bash
  DISK_THRESHOLD=0 TEMP_THRESHOLD=0 python3 monitor.py --once
  ```

- **任意日サマリ**  

  ```bash
  python3 monitor.py --daily --date 2025-05-01
  ```

- **ライブビュー**  

  ```bash
  python3 mjpeg_server.py
  ```

  ブラウザで `http://<RPI_IP>:8080` にアクセスしてください。

---
