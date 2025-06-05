#!/usr/bin/python3
# Picamera2 MJPEG streaming demo (FOV-matched preview)
# 開始エイリアス 5分 camview
# 終了コマンド pkill -2 -f "python.*mjpeg_server.py"

import io
import logging
import socketserver
from http import server
from threading import Condition
from picamera2 import Picamera2
from picamera2.encoders import JpegEncoder, Quality
from picamera2.outputs import FileOutput

# Configuration Constants
PORT = 8000
MAIN_RESOLUTION = (2304, 1296)
LORES_RESOLUTION = (640, 360)
FPS = 10

HTML_PAGE = """
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pi Camera Preview</title>
  <style>
    body, html {
      margin: 0;
      padding: 0;
      background: #000;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    #videoContainer {
      display: flex;
      justify-content: center;
      align-items: center;
      width: 100vw;
      height: 100vh;
      overflow: hidden;
    }
    #camera {
      max-width: 100%;
      max-height: 100%;
      transform: rotate(0deg);
      transition: transform 0.3s ease;
    }
    #controls {
      position: fixed;
      bottom: 10px;
      background: rgba(0,0,0,0.6);
      padding: 10px;
      border-radius: 8px;
    }
    .btn {
      color: white;
      background: #444;
      border: none;
      margin: 0 5px;
      padding: 8px 12px;
      font-size: 14px;
      cursor: pointer;
      border-radius: 4px;
    }
    .btn:hover {
      background: #666;
    }
  </style>
</head>
<body>
  <div id="videoContainer">
    <img id="camera" src="stream.mjpg" />
  </div>
  <div id="controls">
    <button class="btn" onclick="setRotation(0)">0</button>
    <button class="btn" onclick="setRotation(90)">90</button>
    <button class="btn" onclick="setRotation(180)">180</button>
    <button class="btn" onclick="setRotation(270)">270</button>
  </div>

  <script>
    function setRotation(deg) {
      document.getElementById("camera").style.transform = "rotate(" + deg + "deg)";
    }
  </script>
</body>
</html>
"""

class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()

class StreamingHandler(server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ['/', '/index.html']:
            self._send_index()
        elif self.path == '/stream.mjpg':
            self._stream_mjpeg()
        else:
            self.send_error(404)

    def _send_index(self):
        content = HTML_PAGE.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', len(content))
        self.end_headers()
        self.wfile.write(content)

    def _stream_mjpeg(self):
        self.send_response(200)
        self.send_header('Cache-Control', 'no-cache, private')
        self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=FRAME')
        self.end_headers()
        try:
            while True:
                with output.condition:
                    output.condition.wait()
                    frame = output.frame
                self.wfile.write(b'--FRAME\r\n')
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', len(frame))
                self.end_headers()
                self.wfile.write(frame)
                self.wfile.write(b'\r\n')
        except Exception as e:
            logging.warning('Client disconnected %s: %s', self.client_address, str(e))

class StreamingServer(socketserver.ThreadingMixIn, server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True

def setup_camera():
    picam2 = Picamera2()
    config = picam2.create_preview_configuration(
        lores={"size": LORES_RESOLUTION},
        main={"size": MAIN_RESOLUTION},
        controls={
            "FrameDurationLimits": (1000000 // FPS, 1000000 // FPS)}
    )
    picam2.configure(config)
    return picam2

def start_streaming(picam2):
    global output
    output = StreamingOutput()
    picam2.start_recording(JpegEncoder(), FileOutput(output), quality=Quality.LOW)

def run_server():
    address = ('', PORT)
    server = StreamingServer(address, StreamingHandler)
    logging.info(f"Starting MJPEG preview at http://<Pi-IP>:{PORT}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("Server shutdown requested.")
    finally:
        server.shutdown()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    picam2 = setup_camera()
    try:
        start_streaming(picam2)
        run_server()
    finally:
        picam2.stop_recording()
