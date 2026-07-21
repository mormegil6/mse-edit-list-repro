#!/usr/bin/env bash
# Regenerate the repro media. Deterministic; requires only ffmpeg.
#
# The media: a 4 s clip with a white flash at video media-time 0 and a 1 kHz
# beep at audio media-time 1.0 s. The video track is given a 1.0 s leading
# EMPTY EDIT (edts/elst) via -itsoffset, so honoring the edit list delays the
# picture by 1.0 s and the flash lands on top of the beep. Two forms are built:
#
#   plain.mp4   progressive single file (edit list in moov) -> the direct/control player
#   dash/       `ffmpeg -f dash` output: the video init segment KEEPS the elst,
#               and the media segments use moof-relative addressing, so the set
#               is directly appendable through MSE SourceBuffer. This is the same
#               muxer a normal DASH deployment uses.
#
# Only `-f dash` preserves the elst in the init moov. ffmpeg's single-file
# fragmenter (-movflags frag_keyframe) and bento4 mp4fragment both resolve the
# edit into tfdt; GPAC MP4Box -frag keeps the elst but writes an absolute
# tfhd base-data-offset that MSE rejects. Hence the DASH form.
set -e
cd "$(dirname "$0")"
DELAY=1.0; DUR=4

ffmpeg -y -v error -f lavfi -i "color=c=black:s=320x240:r=30:d=${DUR}" \
  -vf "drawbox=x=0:y=0:w=iw:h=ih:c=white:t=fill:enable='lt(t,0.1)'" \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 30 -keyint_min 30 flash.mp4

ffmpeg -y -v error -f lavfi \
  -i "aevalsrc=0.6*sin(2*PI*1000*t)*between(t\,${DELAY}\,${DELAY}+0.1):s=48000:d=${DUR}" \
  -c:a aac -b:a 128k beep.m4a

# mux with the video delayed by an edit list (the mov muxer writes edts/elst)
ffmpeg -y -v error -itsoffset ${DELAY} -i flash.mp4 -i beep.m4a \
  -map 0:v:0 -map 1:a:0 -c copy plain.mp4

# DASH form for the MSE player: init keeps the elst, segments are MSE-legal
rm -rf dash && mkdir -p dash
ffmpeg -y -v error -i plain.mp4 -c copy -map 0 \
  -seg_duration 5 -use_template 0 -use_timeline 0 \
  -f dash dash/stream.mpd

rm -f flash.mp4 beep.m4a
echo "wrote plain.mp4 and dash/ (init-stream0.m4s carries the 1.0 s empty edit)"
