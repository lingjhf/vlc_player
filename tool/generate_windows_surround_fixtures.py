"""Generate 5.1 or 7.1 channel-identification fixtures outside the repository.

The six tones identify FL, FR, FC, LFE, BL and BR in FFmpeg 5.1 channel order.
7.1 adds side-left and side-right tones. These probes test stereo downmixing,
but cannot verify a physical surround system.
"""
import argparse
import json
from pathlib import Path
import subprocess


FORMATS = [
    ('pcm_51', 'wav', 'pcm_s16le', []),
    ('flac_51', 'flac', 'flac', []),
    ('aac_51', 'm4a', 'aac', ['-b:a', '384k']),
    ('ac3_51', 'ac3', 'ac3', ['-b:a', '384k']),
    ('eac3_51', 'eac3', 'eac3', ['-b:a', '384k']),
    ('dts_51', 'dts', 'dca', ['-strict', '-2']),
    ('opus_51', 'opus', 'libopus', ['-b:a', '384k']),
]
FORMATS_71 = [
    ('pcm_71', 'wav', 'pcm_s16le', []),
    ('flac_71', 'flac', 'flac', []),
    ('aac_71', 'm4a', 'aac', ['-b:a', '512k']),
    ('opus_71', 'opus', 'libopus', ['-b:a', '512k']),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--layout', choices=('5.1', '7.1'), default='5.1')
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cases, failures = [], []
    tones = [300, 400, 500, 100, 700, 800] + ([900, 1000] if args.layout == '7.1' else [])
    amplitude = 0.025 if args.layout == '7.1' else 0.035
    signal = '|'.join(f'{amplitude}*sin(2*PI*{hz}*t)' for hz in tones)
    for name, extension, codec, extra in (FORMATS_71 if args.layout == '7.1' else FORMATS):
        path = root / f'{name}.{extension}'
        source = f'aevalsrc={signal}:s=48000:d=12:c={args.layout}'
        command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                   '-f', 'lavfi', '-i', source, '-vn', '-c:a', codec, *extra, str(path)]
        result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=120)
        if result.returncode:
            path.unlink(missing_ok=True)
            failures.append({'name': name, 'error': result.stderr})
            print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
        else:
            cases.append({'name': name, 'path': str(path),
                          'kind': 'downmix_71' if args.layout == '7.1' else 'downmix_51',
                          'encoder': codec, 'channel_tones_hz': tones})
            print('GENERATED', name, flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    (root / 'generation-failures.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
