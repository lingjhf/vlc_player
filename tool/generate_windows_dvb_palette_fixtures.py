"""Generate DVB default-palette bands and a 256-color grid for playback verification.

Requires FFmpeg and PyAV. Pass an existing Matroska DVB sample whose subtitle
track has composition and ancillary page IDs 1. All output, including the
generated reference images, should be written to an external directory such
as E:. Install PyAV outside the repository and add it to PYTHONPATH if needed.
The DVB display sets contain no CLUT definition, so the default tables in
ETSI EN 300 743 section 10 apply.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

import av


def segment(kind, data):
    return b'\x0f' + bytes([kind]) + struct.pack('>HH', 1, len(data)) + data


def display_set(depth, version, grid=False):
    width, height = (560, 192) if grid else (560, 80) if depth == 4 else (360, 80)
    left, top = (80, 350) if grid else (80, 400) if depth == 4 else (180, 400)
    colors = ([0, 1, 2, 3] if depth == 2 else list(range(16)) if depth == 4 else
              [0, 1, 2, 3, 8, 17, 34, 68, 128, 255])
    run = width // (16 if grid else len(colors))
    display = segment(0x14, b'\x00' + struct.pack('>HH', 719, 575))
    page = segment(0x10, bytes([30, (version << 4) | 0x0b, 0, 255])
                   + struct.pack('>HH', left, top))
    depth_index = {2: 1, 4: 2, 8: 3}[depth]
    region = segment(0x11, bytes([0, (version << 4) | 7])
                     + struct.pack('>HH', width, height)
                     + bytes([(depth_index << 5) | (depth_index << 2) | 3,
                              0, 0, 3, 0, 0, 0, 0, 0xf0, 0]))
    if grid:
        lines = []
        for row in range(height // 2):
            colors_in_row = range((row * 2 // 12) * 16, (row * 2 // 12 + 1) * 16)
            lines.append(b'\x12' + b''.join(bytes([0, run]) if color == 0
                                            else bytes([0, 128 + run, color])
                                            for color in colors_in_row) + b'\x00\x00\xf0')
        field = b''.join(lines)
    elif depth == 2:
        bits = ''.join('000011' + format(run - 29, '08b') + format(color, '02b')
                       for color in colors) + '000000'
        bits += '0' * (-len(bits) % 8)
        line = b'\x10' + int(bits, 2).to_bytes(len(bits) // 8, 'big') + b'\xf0'
        field = line * (height // 2)
    elif depth == 4:
        bits = ''.join('000011110000' + format(run - 25, '04b') + format(color, '04b')
                       for color in colors) + '00000000'
        bits += '0' * (-len(bits) % 8)
        line = b'\x11' + int(bits, 2).to_bytes(len(bits) // 8, 'big') + b'\xf0'
        field = line * (height // 2)
    else:
        line = b'\x12' + b''.join(bytes([0, run]) if color == 0
                                   else bytes([0, 128 + run, color])
                                   for color in colors) + b'\x00\x00\xf0'
        field = line * (height // 2)
    obj = struct.pack('>HBHH', 0, (version << 4) | 1, len(field), len(field))
    return display + page + region + segment(0x13, obj + field + field) + segment(0x80, b'')


def run(command):
    subprocess.run(command, check=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    gray = root / 'gray-source.mkv'
    run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
         '-i', 'color=c=0x404040:s=720x576:r=25:d=45', '-i', str(source),
         '-map', '0:v:0', '-map', '1:s:0', '-c:v', 'libx264', '-preset',
         'ultrafast', '-pix_fmt', 'yuv420p', '-c:s', 'copy', '-t', '45', str(gray)])
    cases = []
    for depth, grid in ((2, False), (4, False), (8, False), (8, True)):
        suffix = f'{depth}bit-grid' if grid else f'{depth}bit'
        target = root / f'default-{suffix}.mkv'
        with av.open(str(gray)) as input_file, av.open(str(target), 'w') as output_file:
            subtitle = next(stream for stream in input_file.streams if stream.type == 'subtitle')
            if (subtitle.codec_context.extradata or b'')[:4] != b'\x00\x01\x00\x01':
                raise ValueError('Source must use DVB composition and ancillary page IDs 1')
            mapping = {stream.index: output_file.add_stream_from_template(stream)
                       for stream in input_file.streams if stream.type in ('video', 'subtitle')}
            count = 0
            for packet in input_file.demux():
                if packet.stream.index not in mapping or packet.dts is None:
                    continue
                if packet.stream.type == 'subtitle':
                    replacement = av.packet.Packet(display_set(depth, count % 16, grid))
                    replacement.pts, replacement.dts = packet.pts, packet.dts
                    replacement.duration, replacement.time_base = packet.duration, packet.time_base
                    replacement.stream = mapping[packet.stream.index]
                    output_file.mux(replacement)
                    count += 1
                else:
                    packet.stream = mapping[packet.stream.index]
                    output_file.mux(packet)
            if count < 5:
                raise ValueError('Source must contain at least five subtitle packets')
        reference = root / f'default-{suffix}-reference.png'
        run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-compute_clut', '0',
             '-i', str(target), '-filter_complex', '[0:v:0][0:s:0]overlay',
             '-ss', '3', '-frames:v', '1', str(reference)])
        cases.append({'name': f'dvb_default_{depth}bit_grid' if grid else f'dvb_default_{depth}bit',
                      'path': str(target),
                      'palette_reference': True, 'subtitle_reference': str(reference),
                      'palette_rect': ([80, 350, 560, 192] if grid else
                                       [80, 400, 560, 80] if depth == 4 else [180, 400, 360, 80]),
                      'palette_bands': 16 if grid or depth == 4 else 4 if depth == 2 else 10,
                      'palette_rows': 16 if grid else 1, 'selected_hold_ms': 1000,
                      'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        print(f'GENERATED {target} ({count} subtitle packets)', flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
