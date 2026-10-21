import os
import sys
import time
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

DAEMON_LOG_PATH = "/root/.gemini/antigravity-cli/antigravity-cli-daemon.log"
INSTANCE_NAME = os.environ.get("REMOTE_INSTANCE_NAME", "Render-Cloud-AGY")

def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def stream_daemon_logs():
    """Continuously stream daemon log lines to stdout so they appear in Render logs."""
    os.makedirs(os.path.dirname(DAEMON_LOG_PATH), exist_ok=True)
    if not os.path.exists(DAEMON_LOG_PATH):
        with open(DAEMON_LOG_PATH, "w") as f:
            f.write(f"--- Daemon log initialized at {time.ctime()} ---\n")
    
    try:
        proc = subprocess.Popen(
            ["tail", "-n", "50", "-F", DAEMON_LOG_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        for line in proc.stdout:
            print(f"[DAEMON] {line.rstrip()}", flush=True)
    except Exception as e:
        log(f"Error streaming daemon logs: {e}")

def get_daemon_status():
    try:
        res = subprocess.run(
            ["agy", "remote-control", "status"],
            capture_output=True,
            text=True,
            timeout=10
        )
        out = res.stdout.strip() or res.stderr.strip()
        return out
    except Exception as e:
        return f"Error checking status: {e}"

def restart_daemon():
    log(f"Restarting remote-control daemon as '{INSTANCE_NAME}'...")
    try:
        subprocess.run(["agy", "remote-control", "stop"], capture_output=True, timeout=10)
        time.sleep(2)
        res = subprocess.run(
            ["agy", "remote-control", "start", "--name", INSTANCE_NAME],
            capture_output=True,
            text=True,
            timeout=15
        )
        log(f"Daemon start output: {res.stdout.strip()} {res.stderr.strip()}")
        return res.stdout.strip()
    except Exception as e:
        log(f"Error restarting daemon: {e}")
        return str(e)

def watchdog_loop():
    """Ensures the remote-control daemon stays active continuously."""
    time.sleep(30) # Initial grace period
    consecutive_failures = 0
    while True:
        try:
            status = get_daemon_status()
            if "inactive" in status.lower() or "not running" in status.lower() or "error" in status.lower():
                consecutive_failures += 1
                if consecutive_failures >= 2:
                    log(f"Watchdog detected inactive daemon ({status}). Restarting...")
                    restart_daemon()
                    consecutive_failures = 0
            else:
                consecutive_failures = 0
            time.sleep(25)
        except Exception as e:
            log(f"Watchdog exception: {e}")
            time.sleep(25)

class HealthAndStatusHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/status"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            
            status = get_daemon_status()
            
            daemon_log = ""
            if os.path.exists(DAEMON_LOG_PATH):
                try:
                    with open(DAEMON_LOG_PATH, "r", errors="ignore") as f:
                        lines = f.readlines()
                        daemon_log = "".join(lines[-100:])
                except Exception as e:
                    daemon_log = f"Error reading log: {e}"
            else:
                daemon_log = "No log file found yet."

            html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Antigravity Remote Control - Render</title>
    <style>
        body {{ font-family: monospace; background: #121212; color: #e0e0e0; padding: 20px; }}
        h1 {{ color: #4CAF50; }}
        pre {{ background: #1e1e1e; padding: 15px; border-radius: 5px; overflow-x: auto; border: 1px solid #333; }}
        .badge {{ background: #2e7d32; color: white; padding: 4px 8px; border-radius: 4px; }}
        a {{ color: #64b5f6; }}
    </style>
</head>
<body>
    <h1>Antigravity CLI Remote Control</h1>
    <p>Instance: <b>{INSTANCE_NAME}</b> | Service Status: <span class="badge">ACTIVE</span></p>
    <p>Model: <b>Gemini 3.8 Flash (Medium)</b></p>
    <p>Console: <a href="https://antigravity.google.com" target="_blank">antigravity.google.com</a></p>
    
    <h3>Daemon Status</h3>
    <pre>{status}</pre>
    
    <h3>Recent Daemon Logs (<a href="/log">view raw</a>)</h3>
    <pre>{daemon_log}</pre>
</body>
</html>"""
            self.wfile.write(html.encode("utf-8"))
        
        elif self.path == "/log":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            if os.path.exists(DAEMON_LOG_PATH):
                with open(DAEMON_LOG_PATH, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"Log file not found.")

        elif self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        
        else:
            self.send_response(404)
            self.end_headers()


    def do_POST(self):
        if self.path == '/api/exec':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            import urllib.parse
            params = urllib.parse.parse_qs(post_data)
            cmd = params.get('cmd', [''])[0]
            
            # Simple auth check
            auth_header = self.headers.get('Authorization', '')
            expected_key = 'rnd_Z8ADOZVM12ubAbejCT2thgfmkwJm'
            if not auth_header.endswith(expected_key) and params.get('key', [''])[0] != expected_key:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'Unauthorized')
                return

            if not cmd:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'cmd parameter required')
                return

            log(f'[EXEC] Running command: {cmd}')
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
            output = res.stdout + res.stderr

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(output.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()

    def log_message(self, format, *args):
        if args and "200" in str(args[1]):
            return
        super().log_message(format, *args)

def self_pinger():
    """Pings external Render URL every 8 minutes to prevent container spin-down/sleep."""
    time.sleep(60)
    render_url = os.environ.get("RENDER_EXTERNAL_URL", "https://antigravity-remote-89e9.onrender.com").rstrip("/")
    log(f"Self-pinger started for URL: {render_url}")
    import urllib.request
    while True:
        try:
            req = urllib.request.Request(f"{render_url}/healthz", headers={"User-Agent": "RenderSelfPinger/1.0"})
            with urllib.request.urlopen(req, timeout=20) as resp:
                log(f"Self-ping successful: {resp.status}")
        except Exception as e:
            log(f"Self-ping note: {e}")
        time.sleep(480)

def main():
    port = int(os.environ.get("PORT", 10000))
    log(f"Starting server on port {port}...")
    
    t_stream = threading.Thread(target=stream_daemon_logs, daemon=True)
    t_stream.start()

    t_watch = threading.Thread(target=watchdog_loop, daemon=True)
    t_watch.start()

    t_ping = threading.Thread(target=self_pinger, daemon=True)
    t_ping.start()

    server = HTTPServer(("0.0.0.0", port), HealthAndStatusHandler)
    server.serve_forever()

if __name__ == "__main__":
    main()
