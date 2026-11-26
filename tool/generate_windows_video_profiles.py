"""Generate patterned video profile fixtures and a sample manifest on E:.

Requires an FFmpeg build with the listed encoders. Each failed generation is
recorded explicitly; an unsupported encoder is not a successful playback test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


PROFILES = [
    ('h264_high10', 'libx264', 'yuv420p10le', ['-profile:v', 'high10']),
    ('h264_high422', 'libx264', 'yuv422p10le', ['-profile:v', 'high422']),
    ('h264_high444', 'libx264', 'yuv444p', ['-profile:v', 'high444']),
    ('hevc_main10', 'libx265', 'yuv420p10le', ['-x265-params', 'log-level=error:pools=1']),
    ('vp9_profile2', 'libvpx-vp9', 'yuv420p10le', ['-deadline', 'realtime', '-cpu-used', '8']),
    ('av1_main10', 'libaom-av1', 'yuv420p10le', ['-cpu-used', '8', '-row-mt', '1']),
    ('h261_avi', 'h261', 'yuv420p', []),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--profile', action='append', choices=[p[0] for p in PROFILES],
                        help='Generate only the selected profile; may be repeated')
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, encoder, pixel_format, options in PROFILES:
        if args.profile and name not in args.profile:
            continue
        target = root / f'{name}.{"avi" if name == "h261_avi" else "mkv"}'
        size = '352x288' if name == 'h261_avi' else '320x180'
        command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                   '-f', 'lavfi', '-i', f'testsrc2=size={size}:rate=25:duration=10',
                   '-an', '-c:v', encoder, '-pix_fmt', pixel_format,
                   '-threads', '2', *options, str(target)]
        result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=180)
        if result.returncode or not target.exists() or not target.stat().st_size:
            target.unlink(missing_ok=True)
            rows.append({'name': name, 'status': 'failed', 'error': result.stderr})
            print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
            continue
        rows.append({'name': name, 'status': 'generated', 'path': str(target),
                     'source': 'generated FFmpeg testsrc2', 'encoder': encoder,
                     'pixel_format': pixel_format, 'verify_motion': True,
                     'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        print('GENERATED', name, flush=True)
    # Reuse the public sample reference generator, which recognizes this schema.
    (root / 'downloads.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
