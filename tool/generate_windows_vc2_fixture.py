"""Generate an external VC-2 video and independent playback reference.

The video uses a visible moving pattern, so a blank picture cannot be mistaken
for a successful decode. FFmpeg must include the VC-2 encoder.
"""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    video = root / 'vc2-pattern.mkv'
    reference = root / 'vc2-pattern.rgb'
    common = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y']
    subprocess.run(common + [
        '-f', 'lavfi', '-i', 'testsrc2=s=720x576:r=25:d=8',
        '-c:v', 'vc2', '-threads', '2', '-b:v', '30M', '-pix_fmt',
        'yuv422p', str(video),
    ], check=True)
    subprocess.run(common + [
        '-i', str(video), '-t', '8', '-vf', 'fps=2,scale=96:54',
        '-pix_fmt', 'rgb24', '-f', 'rawvideo', str(reference),
    ], check=True)
    manifest = [{
        'name': 'vc2_pattern', 'path': str(video), 'kind': 'reference_video',
        'reference': str(reference), 'codec': 'dirac',
    }]
    (root / 'manifest.json').write_text(json.dumps(manifest, indent=2),
                                        encoding='utf-8')
    print(f'Generated {video} and {reference}')


if __name__ == '__main__':
    main()
