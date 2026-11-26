"""Generate a simple ProTracker MOD and an independent libopenmpt reference."""
import argparse
import json
import math
from pathlib import Path
import struct
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    module = root / 'sine.mod'
    reference = root / 'sine.f32'

    def title(value, size):
        return value.encode('ascii').ljust(size, b'\0')

    wave = bytes(int(round(100 * math.sin(2 * math.pi * i / 19))) & 255
                 for i in range(38))
    sample = title('sine', 22) + struct.pack('>HBBHH', len(wave) // 2,
                                               0, 64, 0, len(wave) // 2)
    empty_sample = bytes(30)
    # Four orders of the same 64-row pattern; sample 1 loops continuously.
    pattern = bytearray(64 * 4 * 4)
    pattern[:4] = bytes((0x01, 0xac, 0x10, 0x00))  # sample 1, period 428
    module.write_bytes(title('sine probe', 20) + sample + empty_sample * 30
                       + bytes((4, 0x7f)) + bytes(128) + b'M.K.' + pattern + wave)
    # A second distinct note allows two simultaneous players to be checked for
    # isolation. Keep the same sample and use ProTracker period 321 (~583 Hz).
    second_pattern = bytearray(pattern)
    second_pattern[:2] = bytes((0x01, 0x41))
    (root / 'sine-321.mod').write_bytes(
        title('sine probe 2', 20) + sample + empty_sample * 30
        + bytes((4, 0x7f)) + bytes(128) + b'M.K.' + second_pattern + wave)
    subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', 'libopenmpt', '-i', str(module), '-t', '12',
                    '-ac', '1', '-ar', '48000', '-f', 'f32le', str(reference)],
                   check=True)
    cases = [{'name': 'mod_sine', 'path': str(module), 'kind': 'reference_audio',
              'reference': str(reference), 'codec': 'protracker_mod'}]
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    print(f'Generated {module} and {reference}')


if __name__ == '__main__':
    main()
