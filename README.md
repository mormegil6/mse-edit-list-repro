# An empty-edit (elst, media_time = -1) presentation offset: applied by Firefox MSE and by Chromium's non-MSE playback, dropped by Chromium MSE

**Filed as an interoperability clarification, one report per engine and the spec:**

- **Chromium / Blink:** https://issues.chromium.org/issues/537235698
- **WebKit / Safari:** https://bugs.webkit.org/show_bug.cgi?id=316870
- **Gecko / Firefox** (the mirror-image case, on the plain-file path): https://bugzilla.mozilla.org/show_bug.cgi?id=2056945
- **W3C Media Source #377**, the underlying spec discrepancy: https://github.com/w3c/media-source/issues/377

**Source-side fix (merged upstream):** https://github.com/EnvelopSound/Earshot/pull/53
(aligning the track starts at the packager so no edit list is written at all)

Per-engine status is in the [Status](#status-as-of-23-july-2026) section below.

Minimal, self-contained reproduction of an interoperability difference. An fMP4
initialization segment whose video track carries a single leading **empty edit**
(an `elst` entry with `media_time = -1`, `media_rate = 1`, non-zero duration)
gets different A/V alignment across engines and delivery paths, on the **identical
bytes**:

- **Firefox** through MSE delays video presentation by the empty-edit duration (in sync).
- **Chromium** through `<video src>` (not MSE) also delays it (in sync).
- **Chromium** through **Media Source Extensions** does not, so the video plays that much ahead of the audio.

Same file, same browser, two delivery paths that disagree, and two engines that
disagree on the MSE path: that divergence is the core, undeniable observation.

This is the default output of `ffmpeg -f dash` whenever the muxed tracks do not
start at exactly the same timestamp (for example, a live transcoder whose audio
and video begin a fraction of a second apart), so it affects real streams, not
just this synthetic file.

## The precise behavior

The white flash is at video media-time 1.0 s; the 1 kHz beep is at audio media-time
4.0 s. Applying the 3.0 s empty edit delays the picture so the flash lands exactly
on the beep (both at presentation time 4.0 s). (The flash is at 1.0 s rather than 0
so the empty-edit lead-in renders as black, and the flash reads as a discrete event
rather than filling the whole gap.)

| path | flash presented at | `duration` | video `buffered.start` |
|---|---|---|---|
| Chromium, MSE `appendBuffer` | **1.0 s** (3 s before the beep) | **5.0 s** | **0.0 s** (offset not applied) |
| Chromium, `<video src>` (control) | 4.0 s (on the beep) | 8.0 s | n/a (offset applied) |
| Firefox, MSE `appendBuffer` | 4.0 s (on the beep) | 8.0 s | 3.0 s (offset applied) |

The numbers are read straight from the MSE API (`SourceBuffer.buffered`,
`HTMLMediaElement.duration`) and the painted flash frame's `mediaTime`
(`requestVideoFrameCallback`), so there is no measurement ambiguity: Chromium's
MSE places the video track 3.0 s earlier than Firefox's MSE does, on the same bytes.

## What this is and is not claiming

It is **not** "Chromium ignores edit lists." Chromium applies edit lists for
trimming: its own MSE test data includes `tiny-clip.mp4`, which relies on the
`elst` for AAC end trimming (see the reference below). What this report is about is
specifically the **empty edit** (`media_time = -1`) **presentation offset**: an
empty edit inserts a gap before the media (a delay) instead of trimming into it,
and that offset is what MSE does not apply. This report tests only the empty-edit
offset, measured on the bytes in `dash/`; it does not test the non-empty trim case.

## Live demo

**Plain-English explainer (start here):**
https://mormegil6.github.io/mse-edit-list-repro/explained.html

A general-audience walkthrough of what the empty edit is and why the identical
video ends up seconds out of sync in one browser but not another. It embeds an
interactive demo (one player at a time) and a muted-readable timeline strip that
makes the offset visible without sound.

**The reproduction** (this is the exact URL cited in the Chromium issue above):
**https://mormegil6.github.io/mse-edit-list-repro/**

Click **Start**. Under each player an event timeline prints when the video flash
and the audio beep occur. If the offset was applied, the flash reads at 4.0 s, on
the beep (in sync); if it was dropped, the flash reads at 1.0 s, 3 s before the
beep. A badge states the result. The non-MSE control player is shown in every
browser except Firefox (see "the control player" below).

A companion page,
[**`/progressive.html`**](https://mormegil6.github.io/mse-edit-list-repro/progressive.html),
plays the same file through a plain `<video src>` (no MSE) and shows the opposite
split: Chromium applies the offset there (`duration` 8.0 s, flash at 4.0 s), while
Firefox drops it (`duration` 5.0 s, flash at 1.0 s). So Firefox applies this offset
through MSE but not in progressive playback; Chromium is the reverse.

## Reproduce locally

```
git clone https://github.com/mormegil6/mse-edit-list-repro.git
cd mse-edit-list-repro
python3 -m http.server 8000
# open http://localhost:8000/ in Chrome/Chromium, click Start
```

(Serve over HTTP, not a `file://` URL, because MSE fetches the segments.)

## What the file contains (byte-verified)

`plain.mp4` carries 5 s of media behind a 3.0 s leading empty edit (8 s total
presentation, which is why the control row above reports `duration` 8.0 s). Its
video track has a two-entry edit list: the 3.0 s empty edit (`media_time = -1`)
followed by the normal edit. `dash/` is produced from it by `ffmpeg -f dash`; the
video **init segment** (`dash/init-stream0.m4s`)
preserves that empty edit in its `moov`, and the media segments use moof-relative
addressing (`default-base-is-moof`), so they append through MSE.

Confirm the empty edit in the init segment with any box dumper:

```
$ mp4dump dash/init-stream0.m4s | grep -A4 elst
      [elst] size=12+28
        entry_count = 2
        entry/segment duration = 3000    # 3.0 s in the 1000-tick movie timescale
        entry/media time = -1            # empty edit
        entry/media rate = 1

$ MP4Box -diso dash/init-stream0.m4s    # <EditListEntry Duration="3000" MediaTime="-1" MediaRate="1"/>
```

- `index.html` appends `dash/init-stream0.m4s` + `dash/chunk-stream0-00001.m4s` to
  a video `SourceBuffer` and the stream1 pair to an audio `SourceBuffer`.
- The control player just sets `video.src` to `plain.mp4`.

Both players receive the identical encoded media; only the delivery path differs.

## The control player (shown in every browser except Firefox)

The `<video src>` control proves the media is fine outside MSE. In both Chrome and
Safari, `<video src>` applies the offset on the same file, so the control plays in
sync right next to the out-of-sync MSE player, which is the point. It is hidden in
Firefox only, whose progressive `<video src>` path *drops* the offset (a separate
quirk, opposite to Chrome and Safari); showing it there would only distract. Judge
each player on its own flash-vs-beep, never one player against the other.

The full picture, per engine and delivery path, on the identical bytes (measured;
"applies" = flash lands on the beep, `duration` 8 s; "drops" = flash 3 s early,
`duration` 5 s):

| engine | MSE (`appendBuffer`) | non-MSE (`<video src>`) |
|---|---|---|
| Chrome / Blink | drops | applies |
| Safari / WebKit | drops | applies |
| Firefox / Gecko | applies | drops |

*(These are the shipping behaviors reproducible today. Since filing, WebKit trunk
has changed to apply the offset under MSE; see **Status** at the end of "The spec
question this raises" below.)*

Every engine is internally inconsistent between its own two paths, and no two
engines agree on both. In Chrome and Safari, MSE is the deviant path: it drops an
offset the same engine honors in normal `<video src>` playback. That is the core of
the report.

One implementation detail: when the offset is applied through MSE, the video
`SourceBuffer` has an empty gap `[0, 3 s]` at the front, and some engines (Firefox)
stall on autoplay at that gap. The demo seeks the honored player into the media so
it plays and shows the in-sync result rather than sitting on a black frame.

## The spec question this raises

The MSE ISO BMFF byte stream format was clarified in 2014 (W3C Bug 26066) to
require:

> The user agent must support setting the offset from media composition time to
> movie presentation time by handling an Edit Box (edts) containing a single Edit
> List Box (elst) that contains a single edit with media rate one. This edit may
> have a duration of 0 (indicating that it spans all subsequent media) or may
> have a non-zero duration (indicating the total duration of the movie including
> fragments).

The empty-edit **delay** pattern is two entries (an empty edit, then the normal
edit), which is arguably outside the *single* edit the spec mandates, even though
the empty edit itself has `media_rate = 1`. So this is a genuine, answerable
question rather than a clear-cut defect:

> Is applying an empty-edit (`media_time = -1`) presentation offset intended to be
> supported under MSE? If not, is that limitation documented anywhere?

Firefox applies it; `ffmpeg -f dash` emits it by default; and the canonical MSE
test file `bipbopinit.mp4` carries the same `media_time = -1` empty edit (see the
Mozilla reference below). That is the interoperability gap worth resolving, either
by supporting it in Chromium or by documenting that it is out of scope.

### Status (as of 23 July 2026)

Filed as an interoperability clarification (observation, evidence, question)
against every engine and the spec at once. Since then the question has drawn
cross-engine engagement, and the trajectory is toward supporting the offset
rather than declaring it out of scope:

- **Safari / WebKit**: a fix landed in WebKit trunk (7 July 2026, `316626@main`).
  No shipping Safari applies it yet (26.5.2 and 27.0 beta 1 still drop it).
  [WebKit bug 316870](https://bugs.webkit.org/show_bug.cgi?id=316870)
- **Chrome / Blink**: the Chromium issue is assigned, with intent to adapt
  stated, conditional on Safari's rollout; nothing has shipped or changed in a
  released build.
  [Chromium 537235698](https://issues.chromium.org/issues/537235698)
- **Firefox / Gecko**: already applies the offset under MSE (the common
  streaming case); the opposite plain-file behavior is filed separately.
  [Mozilla 2056945](https://bugzilla.mozilla.org/show_bug.cgi?id=2056945)
- **The spec / W3C**: open, with agreement that the byte-stream registry should
  be clarified so there is one written answer.
  [w3c/media-source #377](https://github.com/w3c/media-source/issues/377)
- **Root cause (upstream)**: Envelop Earshot, the streaming server that emitted
  the ambiguous edit, was patched to stop writing it at all: **PR #53, merged**
  (two further contributions, #54 and #55, also merged).

Nothing is fixed in a shipping browser yet; the list above is where each engine
and the spec currently stand.

## Why it matters

`ffmpeg -f dash` (and other packagers) write a track edit list into the init
segment whenever the muxed tracks do not start at the same timestamp. Because the
offset is dropped at the MSE layer, MSE-based players (dash.js, Shaka Player,
hls.js, video.js) are expected to inherit the same desync on Chromium, while the
same stream is in sync on Firefox and in a non-MSE `<video>` element; hls.js has
an independent report (#7432 below). The offset is carried in the init segment, so
a player that drops it produces a desync the application cannot fix by seeking or
buffering.

## Related reports and references

- **W3C, Bug 26066, "Clarify edit list requirements"** (the mandate quoted above):
  https://dvcs.w3.org/hg/html-media/rev/0505b9684488
- **hls.js #7432, "Audio start timestamp offset in fMP4 stream is ignored"**
  (Chrome 138, MSE; audio starts at 0 instead of the 3 s offset in fMP4, correct
  in TS). An analogous presentation offset dropped on the audio side through the
  fMP4/MSE path: https://github.com/video-dev/hls.js/issues/7432
- **Mozilla bug 1140965, "Test file bipbopinit.mp4 contains multiple edits"**
  (the standard MSE test file carries a `media_time = -1` empty edit plus a second
  edit; quotes the single-edit mandate):
  https://bugzilla.mozilla.org/show_bug.cgi?id=1140965
- **Chromium `media/test/data/README.md`** documents `tiny-clip.mp4` as
  "rel[ying] on the edit list (`elst`) for trimming" (AAC end trimming), which is
  direct evidence that Chromium does apply edit-list trimming (so the gap here is
  the empty-edit offset specifically):
  https://github.com/chromium/chromium/blob/main/media/test/data/README.md
- **nzhang227/gapless_audio_mse** (a developer's account, "Seems like most media
  stacks don't handle ELST correctly," with an appendWindow workaround):
  https://github.com/nzhang227/gapless_audio_mse

## Environment

- Reproduced: Chromium 150 (Brave, macOS 14). The behavior is engine-level, so it
  applies to Chrome, Edge, and other Chromium browsers; please add your exact
  Chrome build when filing.
- Firefox 151 applies the offset through MSE (the contrasting behavior).
- Assets built with ffmpeg 8.1.2.

## Rebuild the assets

The committed `plain.mp4` and `dash/` are enough to reproduce. To regenerate them
(requires only ffmpeg), and to change the offset, edit `DELAY` in the script:

```
./make-asset.sh
```
