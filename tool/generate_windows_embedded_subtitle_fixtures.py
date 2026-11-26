"""Mux text and public bitmap subtitles onto solid-color test videos.

Bitmap subtitle inputs are copied without re-encoding. Keep the source samples
and all generated files outside the repository, for example on E:.
"""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--dvd-source', type=Path, required=True)
    parser.add_argument('--pgs-source', type=Path,
                        help='Optional PGS color-test sample')
    parser.add_argument('--dvb-source', type=Path,
                        help='Optional DVB sample with complete palette data')
    parser.add_argument('--dvb-default-source', type=Path,
                        help='Optional DVB sample using default palette colors')
    parser.add_argument('--dvb-default-stream', type=int, default=1,
                        help='Subtitle stream index within the default-palette source')
    parser.add_argument('--dvb-selection-delay-ms', type=int, default=10000,
                        help='Delay before selecting DVB subtitles (sample dependent)')
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    if args.dvb_default_stream < 0 or args.dvb_selection_delay_ms < 0:
        parser.error('DVB stream index and selection delay must be non-negative')
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    srt = root / 'embedded.srt'
    srt.write_text(''.join(
        f'{i + 1}\n00:00:{2 * i:02},000 --> 00:00:{2 * i + 2:02},000\n'
        'VISIBLE EMBEDDED SUBTITLE 12345\n\n' for i in range(22)), encoding='utf-8')
    ass = root / 'embedded.ass'
    ass.write_text('[Script Info]\nScriptType: v4.00+\nPlayResX: 720\nPlayResY: 576\n'
                   '[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
                   'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, '
                   'Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
                   'Style: Default,Arial,36,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,1,0,2,10,10,15,1\n'
                   '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
                   + ''.join(f'Dialogue: 0,0:00:{2 * i:02}.00,0:00:{2 * i + 2:02}.00,'
                             'Default,,0,0,0,,VISIBLE EMBEDDED SUBTITLE 12345\n'
                             for i in range(22)), encoding='utf-8')
    formats = [('matroska_subrip', srt, 'mkv', 'srt'),
               ('matroska_ass', ass, 'mkv', 'ass'),
               ('mp4_mov_text', srt, 'mp4', 'mov_text'),
               ('matroska_dvdsub', args.dvd_source.resolve(), 'mkv', 'copy')]
    if args.pgs_source:
        formats.append(('pgs_red_text', args.pgs_source.resolve(), 'mkv', 'copy'))
    if args.dvb_source:
        formats.extend([('dvb_classic', args.dvb_source.resolve(), 'mkv', 'copy'),
                        ('dvb_transport', args.dvb_source.resolve(), 'ts', 'copy')])
    if args.dvb_default_source:
        formats.append(('dvb_default_palette', args.dvb_default_source.resolve(), 'mkv', 'copy'))
    cases, failures = [], []
    for name, source, ext, subtitle_codec in formats:
        target = root / f'{name}.{ext}'
        pgs = name == 'pgs_red_text'
        dvb = name in ('dvb_classic', 'dvb_transport')
        dvb_default = name == 'dvb_default_palette'
        color = '0x00b000' if pgs else 'red'
        size = '1280x720' if pgs else '720x576'
        loop = ['-stream_loop', '4' if pgs else '12' if dvb_default else '1'] \
            if pgs or dvb or dvb_default else []
        subtitle_stream = args.dvb_default_stream if dvb_default else 0
        command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                   '-f', 'lavfi', '-i', f'color=c={color}:s={size}:r=25:d=45',
                   *loop, '-i', str(source), '-map', '0:v:0', '-map', f'1:s:{subtitle_stream}',
                   '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
                   '-c:s', subtitle_codec, '-t', '45', str(target)]
        result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=120)
        if result.returncode:
            target.unlink(missing_ok=True)
            failures.append({'name': name, 'error': result.stderr})
            print('GENERATION_FAILED', name, result.stderr.strip(), flush=True)
        else:
            case = {'name': name, 'path': str(target), 'subtitle_codec': subtitle_codec}
            if pgs:
                case['red_on_green'] = True
            if dvb:
                case.update(selection_delay_ms=args.dvb_selection_delay_ms,
                            selected_hold_ms=2000)
            if dvb_default:
                case.update(color_on_red=True, default_dvb_palette=True)
            cases.append(case)
            print('GENERATED', name, flush=True)
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    (root / 'generation-failures.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
