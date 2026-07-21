# Chromium MSE ignores a track's edit list (edts/elst)

Minimal, self-contained reproduction: when media is played through **Media Source
Extensions**, Chromium ignores an `edts`/`elst` edit list on the video track.
The same media plays correctly through `<video src>` in Chromium, and correctly
through MSE in Firefox. The result is a fixed, container-encoded A/V desync for
any DASH/CMAF stream whose init segment carries a track edit list, which is the
default output of `ffmpeg -f dash`.

## TL;DR

The video track has a **1.0 s leading empty edit**. A white flash sits at video
media-time 0; a 1 kHz beep sits at audio media-time 1.0 s. Honoring the edit
list delays the picture by 1.0 s, so the flash lands on the beep (in sync).

| through | flash presented at | reported `duration` | video `buffered.start` | in sync? |
|---|---|---|---|---|
| Chromium, MSE `appendBuffer` | **0.0 s** | **4.0 s** | **0.0 s** | no, 1.0 s off |
| Chromium, `<video src>` (control) | 1.0 s | 5.0 s | n/a | yes |
| Firefox, MSE `appendBuffer` | 1.0 s | 5.0 s | 1.0 s | yes |

The MSE numbers are read straight from the MSE API (`SourceBuffer.buffered`,
`HTMLMediaElement.duration`) plus the painted frame's `mediaTime` from
`requestVideoFrameCallback`, so there is no measurement ambiguity: Chromium's
MSE places the video track at presentation time 0 instead of 1.0 s.

## Live demo

**https://mormegil6.github.io/mse-edit-list-repro/**

Click **Start both players**. The left player (MSE) shows the flash immediately;
the right player (direct file) waits 1.0 s. Press **Unmute the MSE player** to
hear the flash and beep 1.0 s apart. A one-line verdict reports the measured
numbers.

## Reproduce locally

```
git clone https://github.com/mormegil6/mse-edit-list-repro.git
cd mse-edit-list-repro
python3 -m http.server 8000
# open http://localhost:8000/ in Chrome/Chromium, click "Start both players"
```

(It must be served over HTTP, not opened as a `file://` URL, because MSE fetches
the segments.)

## Steps

1. Serve the folder and open `index.html` in Chrome/Chromium.
2. Click **Start both players**.
3. Observe the left (MSE) player and its readout.

### Expected

Per the ISO BMFF byte stream format for MSE, the edit list in the initialization
segment is applied. The MSE player should present the first video frame (the
flash) at 1.0 s, in sync with the beep, with `duration` = 5.0 s and video
`buffered.start` = 1.0 s. This is what direct `<video src>` playback does in
Chromium, and what Firefox does through MSE.

### Actual (Chromium)

The MSE player drops the 1.0 s empty edit. The flash is painted at 0.0 s,
`duration` is 4.0 s, and video `buffered.start` is 0.0 s. The audio track (no
edit) still plays the beep at 1.0 s, so audio and video are 1.0 s out of sync.

## What the file contains

`plain.mp4` is a 4 s clip. Its video track carries a two-entry edit list: a 1.0 s
empty edit (`elst` segment_duration = movie_timescale, media_time = -1) followed
by the normal edit. The DASH form in `dash/` is produced from it by
`ffmpeg -f dash`; the video **init segment** (`dash/init-stream0.m4s`) preserves
that empty edit in its `moov`, and the media segments use moof-relative
addressing (`default-base-is-moof`), so they are appendable through MSE.

You can confirm the edit list is present in the init segment with any box dumper,
for example `mp4dump` (Bento4) or `MP4Box -info`:

```
$ mp4dump dash/init-stream0.m4s | grep -A3 elst
      [elst] size=12+28
        entry_count = 2
        entry/segment duration = 1000    # 1.0 s in the 1000-tick movie timescale
        entry/media time = -1            # empty edit

$ MP4Box -info dash/init-stream0.m4s 2>&1 | grep edits
Track has 2 edits: track duration is 00:00:01.000
```

- `index.html` appends `dash/init-stream0.m4s` + `dash/chunk-stream0-00001.m4s`
  to a video `SourceBuffer`, and the stream1 pair to an audio `SourceBuffer`.
- The control player just sets `video.src` to `plain.mp4`.

Both players receive the identical encoded media; only the delivery path differs.

## Why it matters

This is not a synthetic edge case. `ffmpeg -f dash` (and other packagers) write a
track edit list into the init segment whenever the muxed tracks do not start at
exactly the same timestamp, for example when a live transcoder's audio and video
begin a fraction of a second apart. Every player built on MSE (dash.js,
Shaka Player, hls.js fMP4, video.js, and so on) then paints video ahead of audio
by the edit-list amount on Chromium, while the same stream is in sync on Firefox
and in sync in a non-MSE `<video>` element. The desync is baked into the
container, so it cannot be corrected by seeking or by buffering.

## Environment

- Reproduced: Chromium 150 (Brave, macOS 14). The behavior is engine-level, so it
  applies to Chrome, Edge, and other Chromium browsers. Please add your exact
  Chrome build when filing.
- Control (honors the edit list through MSE): Firefox 151.
- Assets built with ffmpeg 8.1.2.

## Rebuild the assets

The committed `plain.mp4` and `dash/` are enough to reproduce. To regenerate them
from scratch (requires only ffmpeg):

```
./make-asset.sh
```
