# Ambient Screen for LG webOS

Fullscreen ambient screensaver for **LG webOS TVs**, with a native **macOS control app** (and an optional Python PC server) to push photos, videos, widgets, and live data over your LAN.

| Piece | Path | Role |
|-------|------|------|
| **Ambient Screen** | [`webos-screensaver/`](webos-screensaver/) | webOS TV app (`com.cupcoding.screensaver`) |
| **Ambient Control** | [`AmbientControl/`](AmbientControl/) | macOS SwiftUI hub (replaces the Python server) |
| PC server (optional) | [`webos-screensaver/server/`](webos-screensaver/server/) | Lightweight Python fallback dashboard |

Designed for **webOS 3.x** (older Chromium): ES5 JavaScript, `XMLHttpRequest`, flexbox — no modern JS/CSS features that break on 2017-era LG sets.

---

## Features

- Large clock & date, photo frame mode, evening tint, offline local backgrounds
- Drag-and-drop widgets from the Mac: weather, prayer times, calendar, world clock, now playing, quotes, countdown, notes
- Push images / MP4 from Mac (or PC) — TV polls every ~3s
- Magic Remote controls on the TV; Wi‑Fi remote (SSAP) from Ambient Control
- Optional Mac screen share and YouTube streaming to the TV (Ambient Control)
- Dynamic Island–style notifications when Ambient is in the foreground

---

## Quick start

### 1. Package & install the TV app

Needs [webOS CLI (`ares-cli`)](https://webostv.developer.lge.com/develop/tools/cli-introduction) and Developer Mode on the TV.

```bash
cd webos-screensaver
ares-package . --no-minify -e server -e README.md
ares-install --device YOUR_TV com.cupcoding.screensaver_*.ipk
ares-launch --device YOUR_TV com.cupcoding.screensaver
```

### 2. Control from Mac (recommended)

```bash
cd AmbientControl
./build-app.sh            # → build/Ambient Control.app
./build-app.sh --install  # also copy to /Applications
```

Ambient Control serves on port **8787**, can launch the TV app with your Mac’s LAN IP, and stores library/state under `~/Library/Application Support/AmbientControl/`.

See [`AmbientControl/README.md`](AmbientControl/README.md) for screen share, YouTube, widgets, and schedules.

### 3. Or use the Python PC server

```bash
cd webos-screensaver
python3 server/server.py
# Dashboard: http://127.0.0.1:8787/dashboard/
```

Enter the PC’s LAN IP on the TV’s first-run setup (remote key **1**). Allow inbound **TCP 8787** on your firewall. Details: [`webos-screensaver/README.md`](webos-screensaver/README.md).

---

## Typical flow

1. Start Ambient Control (or `server.py`) on a machine on the same Wi‑Fi as the TV.
2. Install / launch Ambient Screen on the TV.
3. Upload photos or video, arrange widgets, tap **Show on TV**.
4. If the Mac/PC is off, the TV keeps clock, quotes, and local backgrounds offline.

---

## Video tips (webOS 3.x)

Prefer **H.264 + AAC in MP4**, 1080p or less:

```bash
ffmpeg -i input.mov -c:v libx264 -profile:v main -level 4.0 -pix_fmt yuv420p -c:a aac -movflags +faststart out.mp4
```

---

## Project layout

```
.
├── AmbientControl/          # macOS SwiftUI control app
├── webos-screensaver/       # LG webOS TV app + optional Python server
└── README.md
```

---

## License

Proprietary — © CupCoding. All rights reserved unless otherwise noted.
