"""Capture output audio for session_lifecycle_test.dart on a local test host.

Requires: pip install numpy soundcard, plus FFmpeg on PATH. Android additionally
requires adb and scrcpy. Captures device output only, never a physical microphone.
Start this host, then pass --dart-define=VLC_PLAYER_AV_HOST=http://127.0.0.1:45939
to flutter drive. For USB Android, also run adb reverse tcp:45939 tcp:45939.
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import time
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, default=Path('build/session-verification'))
parser.add_argument('--adb', default='adb')
parser.add_argument('--scrcpy', default='scrcpy')
parser.add_argument('--ffmpeg', default='ffmpeg')
parser.add_argument('--serial', default=None, help='Android USB device serial')
parser.add_argument('--port', type=int, default=45939)
parser.add_argument('--visual-hold', type=float, default=0, help='Extra seconds for visual inspection')
args = parser.parse_args()
import numpy as np
ROOT = args.output_dir.resolve()
ROOT.mkdir(parents=True, exist_ok=True)
SCRCPY, ADB, FFMPEG = args.scrcpy, args.adb, args.ffmpeg
SERIAL = args.serial

def capture_android_screen():
    if SERIAL is None:
        raise ValueError('--serial is required for Android capture')
    def check_foreground():
        windows = subprocess.run([ADB, '-s', SERIAL, 'shell', 'dumpsys', 'window'],
            capture_output=True, text=True, errors='replace', check=True).stdout
        focus = [line for line in windows.splitlines() if 'mCurrentFocus=' in line]
        if not any('com.example.vlc_player_example/' in line for line in focus):
            raise RuntimeError('The VLC example must be foreground for screen capture')
    check_foreground()
    pixels = subprocess.run([ADB, '-s', SERIAL, 'exec-out', 'screencap', '-p'],
        capture_output=True, check=True).stdout
    check_foreground()
    return pixels

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        from urllib.parse import urlparse, parse_qs
        query = parse_qs(urlparse(self.path).query)
        try:
            if urlparse(self.path).path == '/screenshot':
                pixels = capture_android_screen()
                (ROOT / 'android-screen-latest.png').write_bytes(pixels)
                self.send_response(200)
                self.send_header('Content-Type', 'image/png')
                self.end_headers()
                self.wfile.write(pixels)
                return
            platform = query['platform'][0]
            label = query['label'][0]
            frequency = int(query['frequency'][0])
            assert platform in ['windows', 'android']
            assert label in ['initial-red', 'paused', 'queued-blue', 'remounted-red']
            target = ROOT / f'{platform}-{label}.wav'
            print(f'CAPTURE {platform} {label} expected={frequency}', flush=True)
            if platform == 'windows':
                # Keep the actual test window visible long enough for inspection.
                import soundcard as sc
                time.sleep(args.visual_hold)
                speaker = sc.default_speaker()
                loopback = sc.get_microphone(speaker.id, include_loopback=True)
                data = loopback.record(samplerate=48000, numframes=144000, channels=2)
                with wave.open(str(target), 'wb') as out:
                    out.setnchannels(2)
                    out.setsampwidth(2)
                    out.setframerate(48000)
                    out.writeframes((np.clip(data, -1, 1) * 32767).astype('<i2').tobytes())
            else:
                if SERIAL is None: raise ValueError('--serial is required for Android capture')
                screenshot = capture_android_screen()
                (ROOT / f'android-{label}.png').write_bytes(screenshot)
                result = subprocess.run([str(SCRCPY), '-s', SERIAL, '--no-video', '--no-window',
                    '--no-control', '--no-audio-playback', '--audio-codec=raw',
                    f'--record={target}', '--time-limit=6'], capture_output=True, timeout=22,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                (ROOT / f'android-{label}-scrcpy.log').write_bytes(result.stdout + result.stderr)
                if result.returncode: raise RuntimeError((result.stdout + result.stderr).decode(errors='replace'))
            raw = subprocess.run([FFMPEG, '-v', 'error', '-i', str(target), '-f', 'f32le',
                '-acodec', 'pcm_f32le', '-ac', '2', '-ar', '48000', '-'], capture_output=True, check=True).stdout
            samples = np.frombuffer(raw, dtype='<f4').reshape(-1, 2)
            # Ignore device capture startup/teardown transients.
            middle = samples[len(samples)//4:len(samples)*3//4]
            mono = middle.mean(axis=1)
            rms = float(np.sqrt(np.mean(middle**2)))
            spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
            freqs = np.fft.rfftfreq(len(mono), 1/48000)
            spectrum[freqs < 30] = 0
            peak = float(freqs[np.argmax(spectrum)])
            passed = (rms < 0.0002) if frequency == 0 else (rms > 0.00005 and abs(peak-frequency) < 6)
            report = dict(platform=platform, label=label, expected_hz=frequency,
                peak_hz=round(peak, 2), rms=round(rms, 7),
                channels_rms=np.sqrt(np.mean(middle**2,axis=0)).round(7).tolist(),
                seconds=round(len(samples)/48000, 2), passed=bool(passed))
            (ROOT / f'{platform}-{label}.json').write_text(json.dumps(report, indent=2))
            print(json.dumps(report), flush=True)
            body = json.dumps(report).encode()
            self.send_response(200)
        except Exception as error:
            import traceback
            traceback.print_exc()
            body = json.dumps({'error': str(error)}).encode()
            self.send_response(500)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)

print(f'Audio verification host listening on 127.0.0.1:{args.port}', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
