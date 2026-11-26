"""Decode public samples into reference frames/audio and a playback manifest.

Requires downloads.json from download_windows_format_samples.py and FFmpeg's
ffprobe. References and manifests are written beside the E-drive samples.
"""
import argparse
from array import array
import json
from pathlib import Path
import subprocess


def run(command):
    return subprocess.run(command, capture_output=True, text=False, timeout=90)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--ffprobe', required=True)
    args = parser.parse_args()
    root = args.directory.resolve()
    reference = root / 'references'
    reference.mkdir(exist_ok=True)
    cases, failures = [], []
    for item in json.loads((root / 'downloads.json').read_text(encoding='utf-8')):
        if item['status'] not in ('downloaded', 'generated'):
            failures.append({'name': item['name'], 'error': item.get('error', 'download failed')})
            continue
        probe = run([args.ffprobe, '-v', 'error', '-show_entries',
                     'format=duration:stream=codec_type,codec_name', '-of', 'json', item['path']])
        if probe.returncode:
            failures.append({'name': item['name'], 'error': probe.stderr.decode(errors='replace')})
            continue
        metadata = json.loads(probe.stdout)
        media_path = item['path']
        transform = None
        if (item['name'] == 'mp1' and
                float(metadata.get('format', {}).get('duration', '0')) < 3):
            # The archive's sole Layer I clip is only 0.6 s. Repeat its
            # compressed frames so a live loopback capture can observe it.
            media_path = str(root / 'mp1-looped.mp1')
            Path(media_path).write_bytes(Path(item['path']).read_bytes() * 20)
            transform = '20 concatenated copies of the original MPEG audio stream'
        for kind in ('video', 'audio'):
            streams = [s for s in metadata.get('streams', []) if s.get('codec_type') == kind]
            if not streams:
                continue
            name = f"{item['name']}_{kind}"
            target = reference / (name + ('.rgb' if kind == 'video' else '.f32'))
            command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                       '-i', media_path, '-t', '12']
            if kind == 'video':
                command += ['-map', '0:v:0', '-vf', 'fps=2,scale=96:54',
                            '-pix_fmt', 'rgb24', '-f', 'rawvideo']
            else:
                command += ['-map', '0:a:0', '-ac', '1', '-ar', '48000', '-f', 'f32le']
            result = run(command + [str(target)])
            if result.returncode or not target.exists() or target.stat().st_size == 0:
                target.unlink(missing_ok=True)
                failures.append({'name': name, 'error': result.stderr.decode(errors='replace')})
                print('REFERENCE_FAILED', name, flush=True)
                continue
            if kind == 'audio':
                samples = array('f')
                with target.open('rb') as source:
                    samples.frombytes(source.read())
                if not samples or max(map(abs, samples)) < 0.00001:
                    failures.append({'name': name, 'error': 'Decoded reference is silent; choose an audible sample.'})
                    print('REFERENCE_SILENT', name, flush=True)
                    continue
            case = {'name': name, 'path': media_path, 'kind': 'reference_' + kind,
                    'reference': str(target), 'codec': streams[0].get('codec_name'),
                    'duration': metadata.get('format', {}).get('duration'), 'transform': transform}
            if kind == 'video' and item.get('verify_motion'):
                case['verify_motion'] = True
            cases.append(case)
            print('REFERENCE_READY', name, streams[0].get('codec_name'), flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    (root / 'reference-failures.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
    print(f'{len(cases)} ready, {len(failures)} failures')


if __name__ == '__main__':
    main()
