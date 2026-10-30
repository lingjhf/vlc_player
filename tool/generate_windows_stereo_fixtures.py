"""Generate channel-distinct audio fixtures outside the repository.

Left channel contains 440 Hz and right channel 880 Hz. Generation failures are
recorded and never count as successful playback tests.
"""
import argparse
import json
from pathlib import Path
import subprocess


FORMATS = [
    ('pcm_u8_22050', 'wav', 'pcm_u8', 22050, []),
    ('pcm_s24_96000', 'wav', 'pcm_s24le', 96000, []),
    ('pcm_f32_96000', 'wav', 'pcm_f32le', 96000, []),
    ('flac_96000', 'flac', 'flac', 96000, []),
    ('alac_44100', 'm4a', 'alac', 44100, []),
    ('aac_44100', 'm4a', 'aac', 44100, ['-b:a', '192k']),
    ('mp3_48000', 'mp3', 'libmp3lame', 48000, ['-b:a', '192k']),
    ('vorbis_44100', 'ogg', 'libvorbis', 44100, ['-q:a', '5']),
    ('opus_48000', 'opus', 'libopus', 48000, ['-b:a', '192k']),
    ('ac3_48000', 'ac3', 'ac3', 48000, ['-b:a', '192k']),
    ('eac3_48000', 'eac3', 'eac3', 48000, ['-b:a', '192k']),
    ('dts_48000', 'dts', 'dca', 48000, ['-strict', '-2']),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cases, failures = [], []
    for name, extension, codec, rate, extra in FORMATS:
        path = root / f'{name}.{extension}'
        source = f'aevalsrc=0.15*sin(2*PI*440*t)|0.15*sin(2*PI*880*t):s={rate}:d=12:c=stereo'
        command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                   '-f', 'lavfi', '-i', source, '-vn', '-c:a', codec, *extra, str(path)]
        result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=120)
        if result.returncode:
            path.unlink(missing_ok=True)
            failures.append({'name': name, 'error': result.stderr})
            print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
        else:
            cases.append({'name': name, 'path': str(path), 'kind': 'stereo',
                          'left_hz': 440, 'right_hz': 880, 'encoder': codec, 'sample_rate': rate})
            print('GENERATED', name, flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    (root / 'generation-failures.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
