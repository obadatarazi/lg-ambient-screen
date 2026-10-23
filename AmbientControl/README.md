# Ambient Control (macOS)

Native SwiftUI app (Liquid Glass, macOS 26+) that controls the **Ambient Screen** webOS app on the LG TV.
It replaces `webos-screensaver/server/server.py`: the media server is built in.

## Build

```bash
./build-app.sh            # → build/Ambient Control.app
./build-app.sh --install  # also copies it to /Applications
```

Needs the Swift toolchain (Command Line Tools are enough) and `ares-cli` for packaging the TV app.
The macOS 27 SDK makes `@State` a macro whose plugin ships only with Xcode, so views use
`@ViewState` (an alias of the same property wrapper, see `Support/ViewState.swift`).

## How it works

- Serves on port **8787**: `/api/state` (polled by the TV every 3 s), `/media/…` (library, with Range
  support for video), `/tv/…` (the TV app itself, used by the in-app live preview).
- **Launch on TV** runs `ares-launch … -p {"server":"<mac-ip>:8787"}`, so the TV connects without typing an IP.
- Settings changes bump `rev`; the TV re-applies settings only when `rev` changes. `message` and
  `command` are one-shot events keyed by `id`.
- Library and state live in `~/Library/Application Support/AmbientControl/`.
- **Wi-Fi remote** (`TVLink`): LG's SSAP WebSocket on port 3000. Settings are delivered as launch
  parameters (`{server, ambient}`); a running TV app receives them as `webOSRelaunch`. The TV app
  saves the last settings (and a custom wallpaper as data URLs) so it runs without the Mac.
- **Screen share** (`Screen/`): ScreenCaptureKit (picture + Mac sound) → `StreamEncoder`
  (VideoToolbox H.264 + AAC, both passed through AVAssetWriter as fMP4, cut by hand into 0.5 s
  segments at each keyframe) → `/screen/init.mp4` + long-polled `/screen/seg`; the TV plays it
  through Media Source Extensions with sound. LAN only, never the internet. Each `/screen/seg`
  request reports the previous segment's download time and playback jumps; Auto quality aims
  for ~half the measured Wi-Fi speed (1.5 Mbit/s up to the quality's ceiling). Smooth = 720p60,
  Sharp = 1080p30. The TV's player only starts with ~3.5 s buffered (and ignores playbackRate), but keeps
  playing with less: once it plays, `catchUp` in app.js moves later segments earlier on the
  timeline (`timestampOffset`) so they replace unplayed video, leaving ~1.6 s buffered and the
  picture ~2–2.5 s behind. The hub sends every segment in order (a hole forces a 3.5 s refill)
  and only skips ahead when the TV is >3 s behind. WebRTC is not an option: the TV's Chrome 38
  can't handshake with current WebRTC stacks.
- **Dynamic Island** (`webos-screensaver/js/island.js`): `message` = notification
  (title, text, icon, color), `activity` = live timer. Falls back to a native webOS toast when
  another app is on screen.
- **YouTube** (`YouTube/YouTubeStreamer.swift`): yt-dlp resolves H.264 + AAC, ffmpeg remuxes to
  fMP4 HLS segments while downloading, the TV plays them in Ambient (`/yt/<id>-<q>/…`) through
  its speakers. (Launching the TV's YouTube app with a video does not work on webOS 3.5.)
- **Widgets** (`TVState.board`): the Widgets pane has a drag-and-drop layout editor (`BoardEditor`).
  Positions are fractions of the screen, so the TV places them exactly. Old settings migrate to the
  original row.
- **Live data** (`LiveFeeds` → `TVState.live`, no `rev` bump): weather + sunrise/sunset from Open-Meteo,
  prayer times from Aladhan (both by the city in Location), events from Calendar (EventKit),
  Music/Spotify through `osascript`, and the world clock's UTC offset. Each feed only runs while its
  widget is on the board.
- **Schedules** run on the Mac every minute (open Ambient, TV off over SSAP, wallpaper, brightness, tint,
  photo frame).

