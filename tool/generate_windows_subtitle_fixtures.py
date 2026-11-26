"""Create text subtitle probes in an external directory for Windows tests."""
import argparse
import json
from pathlib import Path


TEXT = 'VISIBLE SUBTITLE TEST 12345'
SAMPLES = {
    'subrip.srt': f'1\n00:00:00,000 --> 00:00:12,000\n{TEXT}\n',
    'webvtt.vtt': f'WEBVTT\n\n00:00:00.000 --> 00:00:12.000\n{TEXT}\n',
    'microdvd.sub': f'{{0}}{{300}}{TEXT}\n',
    'subviewer.sub': f'[INFORMATION]\n[TITLE]Test\n[END INFORMATION]\n[SUBTITLE]\n00:00:00.00,00:00:12.00\n{TEXT}\n',
    'sami.smi': f'<SAMI><HEAD><STYLE><!-- P {{ Name: English; lang: en-US; }} --></STYLE></HEAD><BODY><SYNC Start=0><P Class=ENCC>{TEXT}</P></SYNC><SYNC Start=12000><P Class=ENCC>&nbsp;</P></SYNC></BODY></SAMI>',
    'ass.ass': ('[Script Info]\nScriptType: v4.00+\nPlayResX: 352\nPlayResY: 288\n'
                '[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
                'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, '
                'Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
                'Style: Default,Arial,24,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1\n'
                '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
                f'Dialogue: 0,0:00:00.00,0:00:12.00,Default,,0,0,0,,{TEXT}\n'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cases = []
    for name, content in SAMPLES.items():
        path = root / name
        path.write_text(content, encoding='utf-8')
        cases.append({'name': path.stem, 'path': str(path)})
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2), encoding='utf-8')
    print(f'{len(cases)} subtitle probes written to {root}')


if __name__ == '__main__':
    main()
