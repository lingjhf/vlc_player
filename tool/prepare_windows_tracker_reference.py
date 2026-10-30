"""Decode a tracker reference with the Windows OpenMPT default noise filter.

The FFmpeg build must support libopenmpt unless --libxmp is supplied. An FFmpeg
reference uses the same decoding family as the Windows module, so it checks the
playback pipeline and filter rather than independent tracker interpretation.
Write references to an external directory, such as E: on Windows.
"""
import argparse
import ctypes
import json
from pathlib import Path
import re
import subprocess

import numpy as np


def decode_with_libxmp(library, source):
    lib = ctypes.CDLL(str(library))
    ptr = ctypes.c_void_p

    def bind(name, restype, *argtypes):
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = restype, argtypes
        return fn

    create = bind('xmp_create_context', ptr)
    load = bind('xmp_load_module_from_memory', ctypes.c_int, ptr, ptr, ctypes.c_long)
    start = bind('xmp_start_player', ctypes.c_int, ptr, ctypes.c_int, ctypes.c_int)
    play = bind('xmp_play_buffer', ctypes.c_int, ptr, ptr, ctypes.c_int, ctypes.c_int)
    end = bind('xmp_end_player', None, ptr)
    release = bind('xmp_release_module', None, ptr)
    free = bind('xmp_free_context', None, ptr)
    data = source.read_bytes()
    if not data or len(data) > 500_000_000:
        raise ValueError('Tracker source is empty or too large')
    memory = ctypes.create_string_buffer(data)
    context = create()
    if not context:
        raise RuntimeError('Could not create libxmp context')
    loaded = started = False
    try:
        if load(context, memory, len(data)) != 0:
            raise ValueError('libxmp could not decode the tracker source')
        loaded = True
        if start(context, 44100, 0) != 0:
            raise RuntimeError('Could not start libxmp')
        started = True
        chunks = []
        for _ in range(120):
            block = ctypes.create_string_buffer(4410 * 4)
            if play(context, block, len(block), 1) != 0:
                break
            chunks.append(np.frombuffer(block.raw, dtype='<i2').astype(np.float32) / 32768)
        if not chunks:
            raise ValueError('libxmp produced no audio')
        return np.concatenate(chunks)
    finally:
        if started:
            end(context)
        if loaded:
            release(context)
        free(context)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--name', default='tracker_filtered')
    parser.add_argument('--libxmp', type=Path,
                        help='Optional libxmp DLL for an independent decoder reference')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', args.name):
        parser.error('--name must contain only letters, digits, underscores or hyphens')
    source = args.source.resolve(strict=True)
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    decoded = root / f'{args.name}-decoded-44100.f32'
    filtered = root / f'{args.name}-filtered-44100.f32'
    reference = root / f'{args.name}-reference-48000.f32'
    common = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y']
    if args.libxmp:
        audio = decode_with_libxmp(args.libxmp.resolve(strict=True), source)
        audio.astype('<f4').tofile(decoded)
        decoder = 'libxmp'
    else:
        subprocess.run(common + ['-f', 'libopenmpt', '-sample_rate', '44100',
                                 '-i', str(source), '-t', '12', '-ac', '2',
                                 '-ar', '44100', '-f', 'f32le', str(decoded)],
                       check=True, timeout=120)
        audio = np.fromfile(decoded, dtype='<f4')
        decoder = 'libopenmpt'
    if len(audio) < 44100 * 2 or len(audio) % 2 or not np.isfinite(audio).all():
        raise ValueError('Decoded stereo reference is too short or invalid')
    audio = audio.reshape(-1, 2)
    output = np.empty_like(audio)
    output[0] = audio[0] * .5
    output[1:] = (audio[1:] + audio[:-1]) * .5
    output.astype('<f4').tofile(filtered)
    subprocess.run(common + ['-f', 'f32le', '-ar', '44100', '-ac', '2',
                             '-i', str(filtered), '-ac', '1', '-ar', '48000',
                             '-f', 'f32le', str(reference)], check=True, timeout=120)
    cases = [{'name': args.name, 'path': str(source), 'kind': 'reference_audio',
              'reference': str(reference), 'codec': decoder,
              'reference_processing': '44100 Hz stereo, two-sample noise filter, 48000 Hz mono'}]
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    print(f'Generated {reference}')


if __name__ == '__main__':
    main()
