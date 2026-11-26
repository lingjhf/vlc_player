"""Generate an external sustained MIDI note and a Windows playback manifest.

Provide an SF2 file whose General MIDI program 74 produces an audible flute.
The soundfont remains external and is never bundled into the application.
"""
import argparse
import json
from pathlib import Path
import struct


def variable_length(value):
    result = [value & 0x7f]
    value >>= 7
    while value:
        result.insert(0, (value & 0x7f) | 0x80)
        value >>= 7
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--soundfont', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    soundfont = args.soundfont.resolve()
    if not soundfont.is_file():
        parser.error(f'SoundFont does not exist: {soundfont}')
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    # One track, 480 ticks/quarter note, 120 BPM, 30-second sustained A4.
    track = (b'\x00\xff\x51\x03\x07\xa1\x20'  # 500,000 us/quarter
             b'\x00\xc0\x49'                    # GM flute
             b'\x00\x90\x45\x64'                # A4, velocity 100
             + variable_length(60 * 480)
             + b'\x80\x45\x00\x00\xff\x2f\x00')
    midi = root / 'flute-a4.mid'
    midi.write_bytes(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480)
                     + b'MTrk' + struct.pack('>I', len(track)) + track)
    cases = [{
        'name': 'midi_flute_a4', 'path': str(midi), 'kind': 'audio',
        'frequency': 440, 'options': [f'--soundfont={soundfont}',
                                      '--no-synth-chorus', '--no-synth-reverb'],
    }]
    (root / 'manifest.json').write_text(json.dumps(cases, indent=2),
                                        encoding='utf-8')
    print(f'Generated {midi}')


if __name__ == '__main__':
    main()
