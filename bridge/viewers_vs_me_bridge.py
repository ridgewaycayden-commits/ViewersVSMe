import json
import queue
import threading
import tkinter as tk
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from tkinter import ttk

from TikTokLive import TikTokLiveClient
from TikTokLive.events import ConnectEvent, DisconnectEvent, GiftEvent

HOST = "127.0.0.1"
PORT = 8765
EVENTS = queue.Queue()
CURRENT = None
CURRENT_THREAD = None


def push(event):
    EVENTS.put(event)


class Handler(BaseHTTPRequestHandler):
    def _headers(self, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self._headers()
            self.wfile.write(b'{"ok":true}')
            return
        if self.path == "/events":
            batch = []
            while len(batch) < 50:
                try:
                    batch.append(EVENTS.get_nowait())
                except queue.Empty:
                    break
            self._headers()
            self.wfile.write(json.dumps(batch).encode("utf-8"))
            return
        self._headers(404)
        self.wfile.write(b'{"error":"not found"}')

    def log_message(self, *_):
        pass


def start_http():
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


def make_client(username, log):
    username = username.strip()
    if not username.startswith("@"):
        username = "@" + username
    client = TikTokLiveClient(unique_id=username)

    @client.on(ConnectEvent)
    async def connected(event):
        log(f"CONNECTED TO @{str(event.unique_id).lstrip('@')}")

    @client.on(DisconnectEvent)
    async def disconnected(_):
        log("DISCONNECTED")

    @client.on(GiftEvent)
    async def gift(event):
        gift_obj = event.gift
        if gift_obj is None:
            return
        # Ignore intermediate streak packets. Fire once at the end with the final count.
        if getattr(gift_obj, "streakable", False) and getattr(event, "streaking", False):
            return
        gift_name = str(getattr(gift_obj, "name", ""))
        sender = str(getattr(event.user, "unique_id", None) or getattr(event.user, "nickname", "VIEWER"))
        count = int(getattr(event, "repeat_count", 1) or 1)
        payload = {"type": "gift", "sender": sender, "gift": gift_name, "count": count}
        push(payload)
        log(f"GIFT: @{sender} -> {gift_name} x{count}")

    return client


def main():
    threading.Thread(target=start_http, daemon=True).start()

    root = tk.Tk()
    root.title("Viewers VS Me - TikTok LIVE Bridge")
    root.geometry("620x430")
    root.minsize(560, 380)

    frame = ttk.Frame(root, padding=16)
    frame.pack(fill="both", expand=True)
    ttk.Label(frame, text="VIEWERS VS ME - LIVE BRIDGE", font=("Segoe UI", 16, "bold")).pack(anchor="w")
    ttk.Label(frame, text="Enter the username of ANY TikTok creator who is currently LIVE.").pack(anchor="w", pady=(4, 14))

    row = ttk.Frame(frame)
    row.pack(fill="x")
    username = tk.StringVar()
    entry = ttk.Entry(row, textvariable=username)
    entry.pack(side="left", fill="x", expand=True)
    entry.focus()

    output = tk.Text(frame, height=16, state="disabled", font=("Consolas", 10))
    output.pack(fill="both", expand=True, pady=(14, 0))

    def log(msg):
        def write():
            output.configure(state="normal")
            output.insert("end", msg + "\n")
            output.see("end")
            output.configure(state="disabled")
        root.after(0, write)

    def connect():
        global CURRENT, CURRENT_THREAD
        name = username.get().strip()
        if not name:
            log("Enter a TikTok username first.")
            return
        log(f"CONNECTING TO @{name.lstrip('@')}...")
        try:
            CURRENT = make_client(name, log)
        except Exception as exc:
            log(f"SETUP ERROR: {exc}")
            return

        def runner():
            try:
                CURRENT.run()
            except Exception as exc:
                log(f"CONNECTION ERROR: {exc}")
        CURRENT_THREAD = threading.Thread(target=runner, daemon=True)
        CURRENT_THREAD.start()

    ttk.Button(row, text="CONNECT", command=connect).pack(side="left", padx=(10, 0))
    ttk.Label(frame, text=f"Local Roblox endpoint: http://{HOST}:{PORT}/events").pack(anchor="w", pady=(10, 0))
    log("Bridge ready. Type a LIVE creator username and press CONNECT.")
    root.mainloop()


if __name__ == "__main__":
    main()
