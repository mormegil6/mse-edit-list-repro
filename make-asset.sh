#!/usr/bin/env bash
# Regenerate the repro media. Deterministic; requires only ffmpeg.
#
# A white flash sits at video media-time FLASH_AT (1.0 s, NOT 0, so the empty-edit
# lead-in renders as black rather than being filled with the flash frame). A 1 kHz
# beep sits at audio media-time BEEP_AT (= FLASH_AT + SHIFT). The video track is
# given a SHIFT-second leading EMPTY EDIT (edts/elst, media_time = -1) via
# -itsoffset, so honoring the edit list delays the picture by SHIFT and the flash
# lands exactly on the beep (presentation time FLASH_AT + SHIFT). Dropping the
# edit leaves the flash SHIFT seconds early, before the beep. Two forms are built:
#
#   plain.mp4   progressive single file (edit list in moov) -> the direct/control player
#   dash/       `ffmpeg -f dash` output: the video init segment KEEPS the elst,
#               and the media segments use moof-relative addressing, so the set
#               is directly appendable through MSE SourceBuffer. Same muxer a
#               normal DASH deployment uses.
#
# Only `-f dash` preserves the elst in the init moov. ffmpeg's single-file
# fragmenter (-movflags frag_keyframe) and bento4 mp4fragment resolve the edit
# into tfdt; GPAC MP4Box -frag keeps the elst but writes an absolute tfhd
# base-data-offset that MSE rejects. Hence the DASH form.
set -e
cd "$(dirname "$0")"
SHIFT=3.0        # empty-edit duration
FLASH_AT=1.0     # video media time of the flash
DUR=5            # media length (must exceed BEEP_AT)
BEEP_AT=4.0      # = FLASH_AT + SHIFT

ffmpeg -y -v error -f lavfi -i "color=c=black:s=320x240:r=30:d=${DUR}" \
  -vf "drawbox=x=0:y=0:w=iw:h=ih:c=white:t=fill:enable='between(t,${FLASH_AT},${FLASH_AT}+0.15)'" \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 30 -keyint_min 30 flash.mp4

ffmpeg -y -v error -f lavfi \
  -i "aevalsrc=0.85*sin(2*PI*1000*t)*between(t\,${BEEP_AT}\,${BEEP_AT}+0.15):s=48000:d=${DUR}" \
  -c:a aac -b:a 128k beep.m4a

# mux with the video delayed by an edit list (the mov muxer writes edts/elst)
ffmpeg -y -v error -itsoffset ${SHIFT} -i flash.mp4 -i beep.m4a \
  -map 0:v:0 -map 1:a:0 -c copy plain.mp4

# DASH form for the MSE player: init keeps the elst, segments are MSE-legal
rm -rf dash && mkdir -p dash
ffmpeg -y -v error -i plain.mp4 -c copy -map 0 \
  -seg_duration 9 -use_template 0 -use_timeline 0 \
  -f dash dash/stream.mpd

rm -f flash.mp4 beep.m4a
echo "wrote plain.mp4 and dash/ (flash at ${FLASH_AT}s, beep at ${BEEP_AT}s, ${SHIFT}s empty edit)"
