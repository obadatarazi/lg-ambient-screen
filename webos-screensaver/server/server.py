#!/usr/bin/env python3
"""
Ambient Screen control server for LG webOS TV screensaver.
Serves REST API + media files + dashboard. Pure Python 3 stdlib.
Default: http://0.0.0.0:8787
"""
from __future__ import print_function

import json
import mimetypes
import os
import re
import socket
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
MEDIA_DIR = os.path.join(ROOT, "media")
DASHBOARD_DIR = os.path.join(ROOT, "dashboard")
STATE_FILE = os.path.join(ROOT, "state.json")
PORT = int(os.environ.get("AMBIENT_PORT", "8787"))
HOST = os.environ.get("AMBIENT_HOST", "0.0.0.0")

ALLOWED_EXT = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
    ".mp4", ".m4v", ".webm",
}

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
VIDEO_EXT = {".mp4", ".m4v", ".webm"}

_lock = threading.Lock()

DEFAULT_STATE = {
    "showClock": True,
    "showDate": True,
    "showQuotes": True,
    "intervalSec": 30,
    "media": None,
    "playlist": [],
    "playlistIndex": 0,
    "updatedAt": 0,
}


def ensure_dirs():
    if not os.path.isdir(MEDIA_DIR):
        os.makedirs(MEDIA_DIR)
    if not os.path.isdir(DASHBOARD_DIR):
        os.makedirs(DASHBOARD_DIR)


def load_state():
    with _lock:
        if not os.path.isfile(STATE_FILE):
            st = dict(DEFAULT_STATE)
            st["updatedAt"] = int(time.time())
            return st
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            for k, v in DEFAULT_STATE.items():
                if k not in data:
                    data[k] = v
            return data
        except Exception:
            st = dict(DEFAULT_STATE)
            st["updatedAt"] = int(time.time())
            return st


def save_state(st):
    with _lock:
        st["updatedAt"] = int(time.time())
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(st, f, indent=2)
        os.replace(tmp, STATE_FILE)


def guess_type(filename):
    ext = os.path.splitext(filename)[1].lower()
    if ext in VIDEO_EXT:
        return "video"
    return "image"


def media_item_for(name):
    safe = os.path.basename(name)
    path = os.path.join(MEDIA_DIR, safe)
    if not os.path.isfile(path):
        return None
    return {
        "name": safe,
        "url": "/media/" + safe,
        "type": guess_type(safe),
        "size": os.path.getsize(path),
    }


def list_media():
    items = []
    if not os.path.isdir(MEDIA_DIR):
        return items
    for name in sorted(os.listdir(MEDIA_DIR)):
        if name.startswith("."):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext not in ALLOWED_EXT:
            continue
        item = media_item_for(name)
        if item:
            items.append(item)
    return items


def lan_ip():
    """Best-effort LAN IPv4 for dashboard instructions."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "127.0.0.1"


def cors_headers(handler):
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type, Accept")
    handler.send_header("Access-Control-Max-Age", "86400")
    handler.send_header("Cache-Control", "no-store")


class AmbientHandler(BaseHTTPRequestHandler):
    server_version = "AmbientScreen/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _send_json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        cors_headers(self)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, code, data, content_type, extra_headers=None):
        self.send_response(code)
        cors_headers(self)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return None

    def _read_multipart_file(self):
        """Minimal multipart/form-data file parser for field name 'file'."""
        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            return None, "expected multipart/form-data"
        m = re.search(r"boundary=([^;]+)", ctype)
        if not m:
            return None, "missing boundary"
        boundary = m.group(1).strip().strip('"')
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 200 * 1024 * 1024:
            return None, "invalid or too large body"
        body = self.rfile.read(length)
        sep = ("--" + boundary).encode("utf-8")
        parts = body.split(sep)
        for part in parts:
            if b"Content-Disposition" not in part:
                continue
            if b'name="file"' not in part and b"name=file" not in part:
                continue
            # split headers / content
            if b"\r\n\r\n" in part:
                header, content = part.split(b"\r\n\r\n", 1)
            elif b"\n\n" in part:
                header, content = part.split(b"\n\n", 1)
            else:
                continue
            if content.endswith(b"\r\n"):
                content = content[:-2]
            elif content.endswith(b"\n"):
                content = content[:-1]
            if content.endswith(b"--"):
                content = content[:-2]
            if content.endswith(b"\r\n"):
                content = content[:-2]
            fname = "upload.bin"
            hm = re.search(br'filename="([^"]+)"', header)
            if hm:
                fname = hm.group(1).decode("utf-8", "replace")
            fname = os.path.basename(fname)
            ext = os.path.splitext(fname)[1].lower()
            if ext not in ALLOWED_EXT:
                return None, "unsupported file type: " + ext
            # sanitize name
            safe = re.sub(r"[^A-Za-z0-9._-]+", "_", fname)
            if not safe or safe.startswith("."):
                safe = "file_" + uuid.uuid4().hex[:8] + ext
            dest = os.path.join(MEDIA_DIR, safe)
            # avoid overwrite collide
            base, e = os.path.splitext(safe)
            n = 1
            while os.path.exists(dest):
                safe = "%s_%d%s" % (base, n, e)
                dest = os.path.join(MEDIA_DIR, safe)
                n += 1
            with open(dest, "wb") as f:
                f.write(content)
            return media_item_for(safe), None
        return None, "no file field found"

    def do_OPTIONS(self):
        self.send_response(204)
        cors_headers(self)
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path == "/api/state":
            st = load_state()
            # enrich media urls remain relative; TV prepends host
            self._send_json(200, st)
            return

        if path == "/api/media":
            self._send_json(200, {"items": list_media()})
            return

        if path == "/api/info":
            self._send_json(200, {
                "name": "Ambient Screen Server",
                "port": PORT,
                "lanIp": lan_ip(),
                "mediaCount": len(list_media()),
            })
            return

        if path.startswith("/media/"):
            name = os.path.basename(path[len("/media/"):])
            fpath = os.path.join(MEDIA_DIR, name)
            if not os.path.isfile(fpath):
                self._send_json(404, {"error": "not found"})
                return
            ctype = mimetypes.guess_type(fpath)[0] or "application/octet-stream"
            # support simple Range for video seeking on some TVs
            range_hdr = self.headers.get("Range")
            size = os.path.getsize(fpath)
            if range_hdr and range_hdr.startswith("bytes="):
                try:
                    rng = range_hdr[6:].split("-")
                    start = int(rng[0]) if rng[0] else 0
                    end = int(rng[1]) if len(rng) > 1 and rng[1] else size - 1
                    end = min(end, size - 1)
                    length = end - start + 1
                    with open(fpath, "rb") as f:
                        f.seek(start)
                        data = f.read(length)
                    self.send_response(206)
                    cors_headers(self)
                    self.send_header("Content-Type", ctype)
                    self.send_header("Content-Length", str(length))
                    self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
                    self.send_header("Accept-Ranges", "bytes")
                    self.end_headers()
                    self.wfile.write(data)
                    return
                except Exception:
                    pass
            with open(fpath, "rb") as f:
                data = f.read()
            self.send_response(200)
            cors_headers(self)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            self.wfile.write(data)
            return

        # Dashboard static
        if path == "/" or path == "/dashboard" or path == "/dashboard/":
            path = "/dashboard/index.html"

        if path.startswith("/dashboard/"):
            rel = path[len("/dashboard/"):]
            if not rel or rel.endswith("/"):
                rel = "index.html"
            rel = rel.lstrip("/")
            # prevent path escape
            if ".." in rel.split("/"):
                self._send_json(400, {"error": "bad path"})
                return
            fpath = os.path.join(DASHBOARD_DIR, rel)
            if not os.path.isfile(fpath):
                self._send_json(404, {"error": "not found"})
                return
            ctype = mimetypes.guess_type(fpath)[0] or "application/octet-stream"
            with open(fpath, "rb") as f:
                data = f.read()
            self._send_bytes(200, data, ctype)
            return

        self._send_json(404, {"error": "not found", "hint": "Open /dashboard/"})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path == "/api/state":
            body = self._read_json()
            if body is None:
                self._send_json(400, {"error": "invalid json"})
                return
            st = load_state()
            for key in ("showClock", "showDate", "showQuotes"):
                if key in body and isinstance(body[key], bool):
                    st[key] = body[key]
            if "intervalSec" in body:
                try:
                    sec = int(body["intervalSec"])
                    if sec < 5:
                        sec = 5
                    if sec > 600:
                        sec = 600
                    st["intervalSec"] = sec
                except Exception:
                    pass
            if "media" in body:
                st["media"] = body["media"]
            if "playlist" in body and isinstance(body["playlist"], list):
                st["playlist"] = body["playlist"]
            if "playlistIndex" in body:
                try:
                    st["playlistIndex"] = int(body["playlistIndex"])
                except Exception:
                    pass
            # convenience: setActive by name
            if "activeName" in body and body["activeName"]:
                item = media_item_for(body["activeName"])
                if item:
                    st["media"] = item
            save_state(st)
            self._send_json(200, st)
            return

        if path == "/api/upload":
            item, err = self._read_multipart_file()
            if err:
                self._send_json(400, {"error": err})
                return
            self._send_json(200, {"ok": True, "item": item, "items": list_media()})
            return

        if path == "/api/select":
            body = self._read_json() or {}
            name = body.get("name") or body.get("activeName")
            item = media_item_for(name) if name else None
            if not item:
                self._send_json(404, {"error": "media not found"})
                return
            st = load_state()
            st["media"] = item
            # also put at front of playlist if empty
            if not st.get("playlist"):
                st["playlist"] = [item]
                st["playlistIndex"] = 0
            save_state(st)
            self._send_json(200, st)
            return

        if path == "/api/playlist":
            body = self._read_json() or {}
            names = body.get("names") or []
            playlist = []
            for n in names:
                item = media_item_for(n)
                if item:
                    playlist.append(item)
            st = load_state()
            st["playlist"] = playlist
            st["playlistIndex"] = int(body.get("playlistIndex") or 0)
            if playlist:
                idx = st["playlistIndex"] % len(playlist)
                st["media"] = playlist[idx]
            else:
                st["media"] = None
            save_state(st)
            self._send_json(200, st)
            return

        if path == "/api/clear-media":
            st = load_state()
            st["media"] = None
            st["playlist"] = []
            st["playlistIndex"] = 0
            save_state(st)
            self._send_json(200, st)
            return

        self._send_json(404, {"error": "not found"})

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path.startswith("/api/media/"):
            name = os.path.basename(path[len("/api/media/"):])
            fpath = os.path.join(MEDIA_DIR, name)
            if not os.path.isfile(fpath):
                self._send_json(404, {"error": "not found"})
                return
            try:
                os.remove(fpath)
            except Exception as e:
                self._send_json(500, {"error": str(e)})
                return
            st = load_state()
            if st.get("media") and st["media"].get("name") == name:
                st["media"] = None
            st["playlist"] = [p for p in (st.get("playlist") or []) if p.get("name") != name]
            save_state(st)
            self._send_json(200, {"ok": True, "items": list_media(), "state": st})
            return
        self._send_json(404, {"error": "not found"})


def main():
    ensure_dirs()
    # seed state file
    if not os.path.isfile(STATE_FILE):
        save_state(dict(DEFAULT_STATE))

    httpd = ThreadingHTTPServer((HOST, PORT), AmbientHandler)
    ip = lan_ip()
    print("=" * 56)
    print(" Ambient Screen server")
    print(" Dashboard:  http://%s:%d/dashboard/" % (ip, PORT))
    print("             http://127.0.0.1:%d/dashboard/" % PORT)
    print(" TV API:     http://%s:%d/api/state" % (ip, PORT))
    print(" Media dir:  %s" % MEDIA_DIR)
    print(" Enter this IP on the TV setup screen: %s" % ip)
    print("=" * 56)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        httpd.server_close()


if __name__ == "__main__":
    main()
