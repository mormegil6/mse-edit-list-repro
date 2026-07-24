#!/usr/bin/env bash
# Regenerate the explainer-only media for explained.html. Deterministic; ffmpeg only.
#
# WHY THIS IS SEPARATE FROM make-asset.sh:
# index.html / progressive.html and their plain.mp4 + dash/ are the MINIMAL
# reproduction cited in Chromium issue 537235698 (and the WebKit/Mozilla/W3C
# trackers). Those assets are deliberately black-with-one-white-flash and must
# stay byte-identical, so they are NOT regenerated here. explained.html is the
# broad-audience explainer, where a black frame makes the inline player look
# broken in a screenshot. This script builds a SEPARATE clip with a visible test
# card as the base picture, while keeping every property the demo depends on
# identical to the repro asset:
#   - a full-frame WHITE flash at video media-time FLASH_AT (the visual marker
#     the demo detects; it stays an unmistakable full-frame event, not a tint)
#   - a 1 kHz beep at audio media-time BEEP_AT (= FLASH_AT + SHIFT)
#   - a SHIFT-second leading EMPTY EDIT (edts/elst, media_time = -1) on the video
#     track, so the flash and beep coincide only if the edit is honored
#   - the same 320x240 / H.264 baseline / 30 fps as the repro asset, so the MSE
#     codec string (avc1.42c00d) in explained.html is unchanged
#
# Outputs (all SEPARATE from the protected repro assets):
#   explained.mp4     progressive single file (edit list in moov) -> startPlain()
#   dash-explained/   `ffmpeg -f dash` output: the video init segment KEEPS the
#                     elst and the media segments use moof-relative addressing,
#                     so the set is directly appendable through MSE -> startMSE()
set -e
cd "$(dirname "$0")"
SHIFT=3.0        # empty-edit duration
FLASH_AT=1.0     # video media time of the flash
DUR=5            # media length (must exceed BEEP_AT)
BEEP_AT=4.0      # = FLASH_AT + SHIFT

# Base picture: a generated SMPTE-style colour-bar test card (ffmpeg's smptebars,
# no third-party artwork). It is a single static frame, so the player shows
# meaningful content at any moment, and its whole-frame average brightness stays
# well below the demo's white-flash detector, so only the flash reads as "bright".
ffmpeg -y -v error -f lavfi -i "smptebars=s=320x240:r=30:d=${DUR}" \
  -vf "drawbox=x=0:y=0:w=iw:h=ih:c=white:t=fill:enable='between(t,${FLASH_AT},${FLASH_AT}+0.15)'" \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 30 -keyint_min 30 card.mp4

ffmpeg -y -v error -f lavfi \
  -i "aevalsrc=0.85*sin(2*PI*1000*t)*between(t\,${BEEP_AT}\,${BEEP_AT}+0.15):s=48000:d=${DUR}" \
  -c:a aac -b:a 128k ebeep.m4a

# mux with the video delayed by an edit list (the mov muxer writes edts/elst)
ffmpeg -y -v error -itsoffset ${SHIFT} -i card.mp4 -i ebeep.m4a \
  -map 0:v:0 -map 1:a:0 -c copy explained.mp4

# DASH form for the MSE player: init keeps the elst, segments are MSE-legal
rm -rf dash-explained && mkdir -p dash-explained
ffmpeg -y -v error -i explained.mp4 -c copy -map 0 \
  -seg_duration 9 -use_template 0 -use_timeline 0 \
  -f dash dash-explained/stream.mpd

rm -f card.mp4 ebeep.m4a
echo "wrote explained.mp4 and dash-explained/ (test card, flash at ${FLASH_AT}s, beep at ${BEEP_AT}s, ${SHIFT}s empty edit)"
