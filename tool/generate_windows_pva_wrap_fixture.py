#!/usr/bin/env python3
"""Shift a PVA sample's timestamps so its 32-bit video clock wraps quickly.

The payload is not re-encoded. This fixture generator expects PES headers to
be contained in the packet where they start, as in the documented test sample.
"""

import argparse
from pathlib import Path


def packets(data):
    offset = 0
    while offset < len(data):
        if (offset + 8 > len(data) or data[offset:offset + 2] != b'AV'
                or data[offset + 4] != 0x55):
            raise ValueError(f'Invalid PVA header at byte {offset}')
        size = int.from_bytes(data[offset + 6:offset + 8], 'big')
        end = offset + 8 + size
        if end > len(data):
            raise ValueError(f'Truncated PVA packet at byte {offset}')
        yield offset, end
        offset = end


def decode_pts(data):
    return ((data[0] & 14) << 29 | data[1] << 22 |
            (data[2] & 254) << 14 | data[3] << 7 | data[4] >> 1)


def write_pts(data, offset, value):
    value %= 1 << 33
    data[offset] = (data[offset] & 0xf0) | ((value >> 29) & 14) | 1
    data[offset + 1] = (value >> 22) & 255
    data[offset + 2] = ((value >> 14) & 254) | 1
    data[offset + 3] = (value >> 7) & 255
    data[offset + 4] = ((value << 1) & 254) | 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error('Source and output must be different files')

    data = bytearray(args.source.read_bytes())
    locations = list(packets(data))
    video, audio = [], []
    for start, end in locations:
        kind, flags = data[start + 2], data[start + 5]
        payload = start + 8
        if kind == 1 and flags & 0x10:
            if payload + 4 > end:
                raise ValueError('Truncated video timestamp')
            video.append(payload)
        elif kind == 2 and data[payload:payload + 3] == b'\x00\x00\x01':
            if payload + 9 > end:
                raise ValueError('Split PES header is not supported')
            if data[payload + 7] & 0x80:
                if payload + 14 > end:
                    raise ValueError('Truncated PES PTS')
                audio.append(payload + 9)
                if data[payload + 7] & 0x40:
                    if payload + 19 > end:
                        raise ValueError('Truncated PES DTS')
                    audio.append(payload + 14)
    if not video or not audio:
        raise ValueError('Expected video and timestamped audio packets')

    # Place the first audio PTS one second before the 32-bit rollover.
    shift = (1 << 32) - 90000 - decode_pts(data[audio[0]:audio[0] + 5])
    for offset in video:
        value = (int.from_bytes(data[offset:offset + 4], 'big') + shift) % (1 << 32)
        data[offset:offset + 4] = value.to_bytes(4, 'big')
    for offset in audio:
        write_pts(data, offset, decode_pts(data[offset:offset + 5]) + shift)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f'Wrote {args.output}; updated {len(video)} video and {len(audio)} audio timestamps')


if __name__ == '__main__':
    main()
