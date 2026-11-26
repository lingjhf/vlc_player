"""Generate deterministic Windows format probes outside the repository.

Videos alternate between red and blue, and audio streams alternate between
440 Hz and 880 Hz tones. Playback tests
can therefore verify pixels and physical output, not merely track metadata.
Requires an FFmpeg build with the requested encoders. Unsupported encoder/muxer
combinations are recorded as generation failures, never silently counted.
"""
import argparse
import json
from pathlib import Path
import subprocess


VIDEO = [
    ('h264_mp4', 'mp4', 'libx264', []),
    ('h264_mov', 'mov', 'libx264', []),
    ('h264_mkv', 'mkv', 'libx264', []),
    ('h264_ts', 'ts', 'libx264', []),
    ('h264_nut', 'nut', 'libx264', []),
    ('h264_raw', 'h264', 'libx264', []),
    ('hevc_mp4', 'mp4', 'libx265', ['-x265-params', 'log-level=error:pools=1']),
    ('hevc_raw', 'hevc', 'libx265', ['-x265-params', 'log-level=error:pools=1']),
    ('mpeg1_ps', 'mpg', 'mpeg1video', []),
    ('mpeg2_ps', 'mpg', 'mpeg2video', []),
    ('mpeg2_ts', 'ts', 'mpeg2video', []),
    ('mpeg4_avi', 'avi', 'mpeg4', []),
    ('mpeg4_mp4', 'mp4', 'mpeg4', []),
    ('xvid_avi', 'avi', 'libxvid', []),
    ('msmpeg4v2_avi', 'avi', 'msmpeg4v2', []),
    ('msmpeg4v3_avi', 'avi', 'msmpeg4', []),
    ('h263_3gp', '3gp', 'h263', []),
    ('h261_raw', 'h261', 'h261', []),
    ('h263p_avi', 'avi', 'h263p', []),
    ('flv1_flv', 'flv', 'flv', []),
    ('wmv1_asf', 'asf', 'wmv1', []),
    ('wmv2_wmv', 'wmv', 'wmv2', []),
    ('mjpeg_avi', 'avi', 'mjpeg', []),
    ('cinepak_avi', 'avi', 'cinepak', []),
    ('theora_ogg', 'ogv', 'libtheora', []),
    ('vp8_webm', 'webm', 'libvpx', []),
    ('vp9_webm', 'webm', 'libvpx-vp9', []),
    ('av1_mkv', 'mkv', 'libaom-av1', ['-cpu-used', '8']),
]
AUDIO = [
    ('aac_m4a', 'm4a', 'aac', []), ('aac_adts', 'aac', 'aac', []),
    ('mp2', 'mp2', 'mp2', []), ('mp3', 'mp3', 'libmp3lame', []),
    ('ac3', 'ac3', 'ac3', []), ('eac3', 'eac3', 'eac3', []),
    ('dts', 'dts', 'dca', ['-strict', '-2']),
    ('flac', 'flac', 'flac', []), ('alac_m4a', 'm4a', 'alac', []),
    ('vorbis_ogg', 'ogg', 'libvorbis', []), ('opus_ogg', 'opus', 'libopus', []),
    ('speex_ogg', 'spx', 'libspeex', []), ('wavpack', 'wv', 'wavpack', []),
    ('tta', 'tta', 'tta', []), ('wma1_asf', 'wma', 'wmav1', []),
    ('wma2_asf', 'wma', 'wmav2', []),
    ('pcm_s16_wav', 'wav', 'pcm_s16le', []),
    ('pcm_s16_aiff', 'aiff', 'pcm_s16be', []),
    ('pcm_s16_caf', 'caf', 'pcm_s16le', []),
    ('pcm_s16_au', 'au', 'pcm_s16be', []),
    ('pcm_alaw_wav', 'wav', 'pcm_alaw', []),
    ('pcm_mulaw_wav', 'wav', 'pcm_mulaw', []),
    ('adpcm_ima_wav', 'wav', 'adpcm_ima_wav', []),
    ('adpcm_ms_wav', 'wav', 'adpcm_ms', []),
    ('amr_nb', 'amr', 'libopencore_amrnb', ['-ar', '8000', '-ac', '1']),
    ('amr_wb', 'awb', 'libvo_amrwbenc', ['-ar', '16000', '-ac', '1', '-f', 'amr']),
]
AV = [
    ('av_h264_aac_mp4', 'mp4', 'libx264', 'aac'),
    ('av_hevc_aac_mp4', 'mp4', 'libx265', 'aac'),
    ('av_mpeg4_mp3_avi', 'avi', 'mpeg4', 'libmp3lame'),
    ('av_mpeg2_mp2_ps', 'mpg', 'mpeg2video', 'mp2'),
    ('av_mpeg2_ac3_ts', 'ts', 'mpeg2video', 'ac3'),
    ('av_wmv2_wma2_asf', 'asf', 'wmv2', 'wmav2'),
    ('av_h264_aac_flv', 'flv', 'libx264', 'aac'),
    ('av_vp8_vorbis_webm', 'webm', 'libvpx', 'libvorbis'),
    ('av_vp9_opus_webm', 'webm', 'libvpx-vp9', 'libopus'),
    ('av_h264_flac_mkv', 'mkv', 'libx264', 'flac'),
    ('av_theora_vorbis_ogv', 'ogv', 'libtheora', 'libvorbis'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cases, failures = [], []
    for kind, formats in [('video', VIDEO), ('audio', AUDIO)]:
        for index, (name, ext, codec, extra) in enumerate(formats):
            path = root / f'{name}.{ext}'
            color = 'red' if index % 2 == 0 else 'blue'
            frequency = 440 if index % 2 == 0 else 880
            source = (f'color=c={color}:s=352x288:r=25:d=10' if kind == 'video'
                      else f'sine=frequency={frequency}:sample_rate=48000:duration=10')
            cmd = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                   '-f', 'lavfi', '-i', source]
            if kind == 'video':
                cmd += ['-an', '-c:v', codec, '-pix_fmt', 'yuv420p', '-threads', '2']
            else:
                cmd += ['-vn', '-c:a', codec]
            cmd += extra + [str(path)]
            result = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
            if result.returncode:
                path.unlink(missing_ok=True)
                failures.append({'name': name, 'codec': codec, 'error': result.stderr})
                print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
            else:
                cases.append({'name': name, 'path': str(path), 'kind': kind,
                              'encoder': codec, **({'color': color, 'width': 352, 'height': 288} if kind == 'video'
                                                    else {'frequency': frequency})})
                print('GENERATED', name, flush=True)
    for index, (name, ext, video_codec, audio_codec) in enumerate(AV):
        path = root / f'{name}.{ext}'
        color = 'red' if index % 2 == 0 else 'blue'
        frequency = 440 if index % 2 == 0 else 880
        cmd = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
               '-f', 'lavfi', '-i', f'color=c={color}:s=352x288:r=25:d=10',
               '-f', 'lavfi', '-i', f'sine=frequency={frequency}:sample_rate=48000:duration=10',
               '-map', '0:v:0', '-map', '1:a:0', '-c:v', video_codec,
               '-pix_fmt', 'yuv420p', '-threads', '2', '-c:a', audio_codec]
        if video_codec == 'libx265':
            cmd += ['-x265-params', 'log-level=error:pools=1']
        result = subprocess.run(cmd + [str(path)], capture_output=True, text=True, errors='replace')
        if result.returncode:
            path.unlink(missing_ok=True)
            failures.append({'name': name, 'codec': video_codec + '/' + audio_codec, 'error': result.stderr})
            print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
        else:
            cases.append({'name': name, 'path': str(path), 'kind': 'av', 'color': color, 'width': 352, 'height': 288,
                          'frequency': frequency, 'encoder': video_codec + '/' + audio_codec})
            print('GENERATED', name, flush=True)
    name = 'mpeg2_anamorphic'
    path = root / f'{name}.mpg'
    result = subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'color=red:s=720x576:r=25:d=10,setdar=16/9',
        '-c:v', 'mpeg2video', '-threads', '2', str(path)],
        capture_output=True, text=True, errors='replace')
    if result.returncode:
        path.unlink(missing_ok=True)
        failures.append({'name': name, 'codec': 'mpeg2video', 'error': result.stderr})
        print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
    else:
        cases.append({'name': name, 'path': str(path), 'kind': 'video', 'color': 'red',
                      'width': 720, 'height': 576, 'pixel_aspect_ratio': 64 / 45,
                      'encoder': 'mpeg2video'})
        print('GENERATED', name, flush=True)
    name = 'mpeg2_dvd_lpcm'
    path = root / f'{name}.vob'
    result = subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'color=c=red:s=720x576:r=25:d=12',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=12',
        '-map', '0:v', '-map', '1:a', '-c:v', 'mpeg2video', '-threads', '2',
        '-c:a', 'pcm_dvd', '-ar', '48000', '-ac', '2', '-f', 'vob', str(path)],
        capture_output=True, text=True, errors='replace')
    if result.returncode:
        path.unlink(missing_ok=True)
        failures.append({'name': name, 'codec': 'mpeg2video/pcm_dvd', 'error': result.stderr})
        print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
    else:
        cases.append({'name': name, 'path': str(path), 'kind': 'av', 'color': 'red',
                      'width': 720, 'height': 576, 'frequency': 440,
                      'encoder': 'mpeg2video/pcm_dvd'})
        print('GENERATED', name, flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    (root / 'generation-failures.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
    print(f'{len(cases)} generated, {len(failures)} failed')


if __name__ == '__main__':
    main()
