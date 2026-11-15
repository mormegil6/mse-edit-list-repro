#!/usr/bin/env python3
"""Rewrite an MP4's movie timescale without touching the media.

Sets mvhd.timescale to NEW and rescales every field that ISO/IEC 14496-12
expresses in the movie timescale: mvhd.duration, each tkhd.duration and each
elst segment_duration. Media timescales (mdhd), sample tables and mdat are left
byte-identical. Version-0 boxes only; exits on anything else.

  patch-movie-timescale.py IN.mp4 OUT.mp4 NEW_TIMESCALE
"""
import struct, sys

src, dst, new_ts = sys.argv[1], sys.argv[2], int(sys.argv[3])
b = bytearray(open(src, 'rb').read())
CONTAINERS = {b'moov', b'trak', b'edts', b'mdia'}
old_ts = None
log = []


def scale(off, label):
    v = struct.unpack_from('>I', b, off)[0]
    nv, rem = divmod(v * new_ts, old_ts)
    if rem:
        sys.exit(f'{label}: {v} does not rescale exactly')
    struct.pack_into('>I', b, off, nv)
    log.append(f'{label}: {v} -> {nv}')


def walk(start, end, pass_no):
    global old_ts
    p = start
    while p + 8 <= end:
        size, typ = struct.unpack_from('>I4s', b, p)
        if size < 8:
            sys.exit(f'unsupported box size {size} at {p}')
        body = p + 8
        if typ in (b'mvhd', b'tkhd', b'elst') and b[body] != 0:
            sys.exit(f'{typ.decode()} version {b[body]} not supported')
        if typ == b'mvhd' and pass_no == 1:
            old_ts = struct.unpack_from('>I', b, body + 12)[0]
        elif typ == b'mvhd' and pass_no == 2:
            struct.pack_into('>I', b, body + 12, new_ts)
            log.append(f'mvhd.timescale: {old_ts} -> {new_ts}')
            scale(body + 16, 'mvhd.duration')
        elif typ == b'tkhd' and pass_no == 2:
            tid = struct.unpack_from('>I', b, body + 12)[0]
            scale(body + 20, f'tkhd[{tid}].duration')
        elif typ == b'elst' and pass_no == 2:
            n = struct.unpack_from('>I', b, body + 4)[0]
            for i in range(n):
                scale(body + 8 + 12 * i, f'elst entry {i} segment_duration')
        elif typ in CONTAINERS:
            walk(body, p + size, pass_no)
        p += size


walk(0, len(b), 1)
if old_ts is None:
    sys.exit('no mvhd found')
walk(0, len(b), 2)
open(dst, 'wb').write(b)
print('\n'.join(log))
