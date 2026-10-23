# Ambient Screen (LG webOS 3.9)

Elegant fullscreen screensaver for LG webOS TVs, plus an optional **PC control server** so you can push images/videos from your computer.

- **App ID:** `com.cupcoding.screensaver`
- **Title:** Ambient Screen
- **Project path:** `/workspace/webos-screensaver/`

Designed for **webOS 3.9** (older Chromium): ES5 JavaScript, `XMLHttpRequest`, flexbox layouts, no optional chaining / nullish coalescing / CSS grid dependency in the TV UI.

---

## Features (TV app)

- Large digital clock + full date (position, size, weight and colour set from the Mac)
- Widgets placed anywhere on screen from the Mac's layout editor, each in small / medium / large:
  date, quote, clock (analog / digital / stacked), weather, world clock, calendar events,
  now playing, prayer times, countdown, notes
- Weather icons follow the time of day (sun, moon, sunrise, sunset) and the conditions;
  optional rain / snow / clouds / stars over the wallpaper
- Photo frame (playlist timer + small corner clock) and a warm evening tint
- 20+ rotating inspirational quotes
- Soft animated gradient orbs + 4 local abstract backgrounds (works fully offline)
- Optional remote media (images / MP4) from your PC
- Magic Remote controls (see below)
- First-run setup to enter PC LAN IP (saved in `localStorage`)
- Offline fallback if the PC server is unreachable

---

## Remote key bindings (TV)

| Key | Action |
|-----|--------|
| Left / Right | Previous / next quote |
| Up | Cycle color theme |
| Down | Cycle brightness |
| OK / Enter | Pause / resume auto-rotate |
| Back | Toggle help overlay |
| Red | Next local background |
| Green | Next quote |
| Yellow | Cycle theme |
| Blue | Cycle brightness |
| **1** | Open PC server IP setup |

Setup screen: **Red** = Save & Connect, **Green** / **Back** = Offline mode.

---

## PC control server

Location: `server/server.py` (Python 3 standard library only).

### Start the server (on your PC)

```bash
cd server
python3 server.py
```

Or from the project root:

```bash
python3 server/server.py
```

Default listen: `0.0.0.0:8787`

Then open the dashboard in a browser:

```
http://127.0.0.1:8787/dashboard/
http://YOUR_LAN_IP:8787/dashboard/
```

The dashboard shows your LAN IP — enter that same IP on the TV setup screen.

Put files in `server/media/` or upload via the dashboard. Supported:

- Images: `.jpg` `.jpeg` `.png` `.gif` `.webp` `.bmp`
- Video: `.mp4` `.m4v` `.webm`

### Firewall

Allow inbound **TCP 8787** on your PC (private/home network). The TV and PC must be on the same LAN.

### API (for reference)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/state` | TV polls this every ~3s |
| POST | `/api/state` | Update showClock / showDate / showQuotes / intervalSec / media |
| GET | `/api/media` | List media library |
| POST | `/api/upload` | multipart field `file` |
| POST | `/api/select` | `{ "name": "photo.jpg" }` |
| POST | `/api/playlist` | `{ "names": ["a.jpg","b.mp4"] }` |
| POST | `/api/clear-media` | Clear remote media |
| DELETE | `/api/media/<name>` | Delete a file |
| GET | `/media/<name>` | Raw media (CORS + Range for video) |

CORS is open (`*`) so the packaged TV app origin can call the API.

---

## Video codec notes (webOS 3.9)

Prefer **H.264 (AVC) + AAC in MP4**. Many 2017-era LG sets struggle with VP9 / HEVC / high-bitrate 4K in HTML5 `<video>`. Keep clips modest (1080p or less, baseline/main profile H.264) for best results. If a video fails to play, the TV stays on the previous frame/background — try re-encoding:

```bash
ffmpeg -i input.mov -c:v libx264 -profile:v main -level 4.0 -pix_fmt yuv420p -c:a aac -movflags +faststart out.mp4
```

---

## Package for the TV (on a machine with ares-cli)

Do **not** need root — Developer Mode is enough to install the `.ipk`.

```bash
cd /path/to/webos-screensaver
ares-package .
```

This produces something like:

```
com.cupcoding.screensaver_1.0.0_all.ipk
```

Install (example device name `lg-tv`):

```bash
ares-install --device lg-tv com.cupcoding.screensaver_1.0.0_all.ipk
ares-launch --device lg-tv com.cupcoding.screensaver
```

Or copy the `.ipk` via USB / Dev Mode tools if you prefer.

**Important:** Package the **TV app root** (folder containing `appinfo.json`, `index.html`, `css/`, `js/`, `images/`, `icon.png`). Do **not** include the need to run the Python server on the TV — the server stays on your PC. The `server/` folder is for the PC only; you may exclude it from the package if you want a smaller `.ipk`:

```bash
ares-package . --no-minify -e server -e README.md
```

(Exact `-e` / exclude flags depend on your ares-cli version; alternatively temporarily move `server/` aside before packaging.)

---

## Project layout

```
webos-screensaver/
  appinfo.json
  index.html
  icon.png
  README.md
  css/style.css
  js/app.js
  images/bg1.jpg … bg9.jpg
  server/
    server.py
    state.json          (created at runtime)
    media/              (uploads + samples)
    dashboard/
      index.html
      style.css
      dashboard.js
```

---

## Typical flow

1. Start `python3 server/server.py` on the PC.
2. Open the dashboard, upload photos/videos, click **Show on TV**.
3. Package & install the TV app; enter the PC IP on first launch.
4. TV polls `/api/state` and displays the selected media; if the PC is off, clock/quotes/local gradients continue.
