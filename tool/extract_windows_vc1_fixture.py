"""Extract a framed VC-1 elementary stream from an ASF/WMV sample.

Requires PyAV. Packets are not decoded or re-encoded: ASF sequence and
entrypoint headers and per-frame start codes are restored to form an
elementary stream. Write outputs to a dedicated external directory.
"""
import argparse
import hashlib
import json
from pathlib import Path

import av


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=20)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error('--seconds must be positive')
    source = args.source.resolve(strict=True)
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    target = root / 'vc1_framed.vc1'
    if target == source:
        raise ValueError('Source and output must be different files')
    with av.open(str(source)) as container, target.open('wb') as output:
        video = next((s for s in container.streams if s.type == 'video'), None)
        if video is None or video.codec_context.name != 'vc1':
            raise ValueError('Source must contain a VC-1 video stream')
        extra = video.codec_context.extradata or b''
        offset = extra.find(b'\x00\x00\x01\x0f')
        if offset < 0:
            raise ValueError('Source does not contain a VC-1 sequence header')
        output.write(extra[offset:])
        count = 0
        for packet in container.demux(video):
            if not packet.size or packet.pts is None:
                continue
            if packet.pts * float(packet.time_base) > args.seconds:
                break
            data = bytes(packet)
            if not data.startswith(b'\x00\x00\x01'):
                output.write(b'\x00\x00\x01\x0d')
            output.write(data)
            count += 1
        if not count:
            raise ValueError('Source contained no timed video packets')
        output.write(b'\x00\x00\x01\x0a')
    entry = {'name': 'vc1_framed', 'path': str(target), 'status': 'generated',
             'size': target.stat().st_size, 'sha256': digest(target),
             'source': str(source), 'source_sha256': digest(source),
             'transform': 'VC-1 sequence header and frame start codes restored; packets copied',
             'packet_count': count}
    (root / 'downloads.json').write_text(json.dumps([entry], indent=2), encoding='utf-8')
    print(f'Generated {target} with {count} video packets')


if __name__ == '__main__':
    main()
