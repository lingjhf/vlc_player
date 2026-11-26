"""Capture output audio for session_lifecycle_test.dart on a local test host.

Requires: pip install numpy soundcard, plus FFmpeg on PATH. Android additionally
requires adb and scrcpy. Captures device output only, never a physical microphone.
Start this host, then pass --dart-define=VLC_PLAYER_AV_HOST=http://127.0.0.1:45939
to flutter drive. For USB Android, also run adb reverse tcp:45939 tcp:45939.
"""
import argparse
import ctypes
import io
import json
import re
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
parser.add_argument('--capture-seconds', type=float, default=3, help='Windows loopback duration')
parser.add_argument('--reference-manifest', type=Path, help='Optional external sample manifest')
args = parser.parse_args()
import numpy as np
import soundcard as sc
from dvb_palette_reference import compare_palette_reference
from reference_audio import compare_reference_audio
from windows_audio_capture import apply_capture_integrity, record_loopback
ROOT = args.output_dir.resolve()
ROOT.mkdir(parents=True, exist_ok=True)
SCRCPY, ADB, FFMPEG = args.scrcpy, args.adb, args.ffmpeg
SERIAL = args.serial
REFERENCES = {entry['name']: entry for entry in json.loads(args.reference_manifest.read_text(encoding='utf-8'))} if args.reference_manifest else {}
MIN_REFERENCE_CORRELATION = 0.8

def compare_stereo_tones(samples, left_hz, right_hz):
    if left_hz <= 0 or right_hz <= 0 or abs(left_hz - right_hz) < 20:
        raise ValueError('Stereo frequencies must be positive and distinct')
    middle = samples[len(samples)//4:len(samples)*3//4]
    if len(middle) < 1000:
        raise ValueError('Capture is too short for stereo comparison')
    freqs = np.fft.rfftfreq(len(middle), 1/48000)
    spectra = np.abs(np.fft.rfft(middle * np.hanning(len(middle))[:, None], axis=0))
    peaks, ratios, channel_rms = [], [], []
    for channel, (wanted_hz, other_hz) in enumerate(((left_hz, right_hz), (right_hz, left_hz))):
        spectrum = spectra[:, channel].copy()
        spectrum[freqs < 30] = 0
        peaks.append(round(float(freqs[np.argmax(spectrum)]), 2))
        wanted = float(spectrum[np.abs(freqs-wanted_hz) < 6].max(initial=0))
        other = float(spectrum[np.abs(freqs-other_hz) < 6].max(initial=0))
        ratios.append(other / wanted if wanted > 0 else None)
        channel_rms.append(float(np.sqrt(np.mean(middle[:, channel] ** 2))))
    passed = all(channel_rms[i] > 0.00005 and abs(peaks[i] - expected) < 6 and
                 ratios[i] is not None and ratios[i] < 0.2
                 for i, expected in enumerate((left_hz, right_hz)))
    return {'expected_channels_hz': [left_hz, right_hz], 'channel_peaks_hz': peaks,
            'opposite_tone_ratios': ratios, 'channel_rms': channel_rms, 'passed': passed}

def compare_surround_downmix(samples, layout):
    # The fixture assigns FL/FR/FC/LFE/BL/BR to these distinct tones.
    # A stereo endpoint should receive front and surround on their respective
    # sides and center on both. LFE is reported but may legitimately be omitted.
    middle = samples[len(samples)//4:len(samples)*3//4]
    if len(middle) < 1000:
        raise ValueError('Capture is too short for surround downmix comparison')
    freqs = np.fft.rfftfreq(len(middle), 1/48000)
    spectra = np.abs(np.fft.rfft(middle * np.hanning(len(middle))[:, None], axis=0))
    if layout == '5.1':
        tones = (100, 300, 400, 500, 700, 800)
        channels = (((300, 500, 700), (400, 800)), ((400, 500, 800), (300, 700)))
    elif layout == '7.1':
        tones = (100, 300, 400, 500, 700, 800, 900, 1000)
        channels = (((300, 500, 700, 900), (400, 800, 1000)),
                    ((400, 500, 800, 1000), (300, 700, 900)))
    else:
        raise ValueError('Unsupported surround layout')
    levels = [{str(hz): float(spectra[np.abs(freqs-hz) < 6, channel].max(initial=0))
               for hz in tones} for channel in range(2)]
    checks = []
    for channel, (wanted, rejected) in enumerate(channels):
        scale = max(levels[channel][str(hz)] for hz in wanted)
        checks.append(scale > 0.01 and
                      all(levels[channel][str(hz)] > scale * 0.1 for hz in wanted) and
                      all(levels[channel][str(hz)] < scale * 0.2 for hz in rejected))
    return {'channel_tone_levels': levels, 'passed': all(checks)}

def capture_windows_region(subtitle_size=None):
    """Inspect only the center of the foreground example's client area."""
    from ctypes import wintypes
    from PIL import ImageGrab

    user32 = ctypes.WinDLL('user32', use_last_error=True)
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    user32.SetProcessDPIAware()
    hwnd = user32.GetForegroundWindow()
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    handle = kernel32.OpenProcess(0x1000, False, pid.value)
    if not hwnd or not handle:
        raise RuntimeError('Cannot inspect foreground process')
    try:
        name = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(name))
        if not kernel32.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)):
            raise OSError(ctypes.get_last_error(), 'QueryFullProcessImageNameW')
        if Path(name.value).name.lower() != 'vlc_player_example.exe':
            raise RuntimeError('The VLC example must be foreground for screen capture')
    finally:
        kernel32.CloseHandle(handle)
    rect = wintypes.RECT()
    origin = wintypes.POINT(0, 0)
    if not user32.GetClientRect(hwnd, ctypes.byref(rect)) or not user32.ClientToScreen(hwnd, ctypes.byref(origin)):
        raise OSError(ctypes.get_last_error(), 'Cannot locate example client area')
    width, height = rect.right - rect.left, rect.bottom - rect.top
    if width < 160 or height < 120:
        raise RuntimeError('Example client area is too small')
    cx, cy = origin.x + width // 2, origin.y + height // 2
    user32.GetDpiForWindow.argtypes = [wintypes.HWND]
    user32.GetDpiForWindow.restype = wintypes.UINT
    dpi = user32.GetDpiForWindow(hwnd) or 96
    if subtitle_size:
        video_width, video_height = subtitle_size
        if video_width <= 0 or video_height <= 0:
            raise ValueError('Invalid video dimensions')
        scale = min(min(width, 640 * dpi / 96) / video_width,
                    min(height, 360 * dpi / 96) / video_height)
        render_width, render_height = video_width * scale, video_height * scale
        bbox = (int(cx - render_width * .42), int(cy + render_height * .08),
                int(cx + render_width * .42), int(cy + render_height * .48))
    else:
        bbox = (cx - 40, cy - 40, cx + 40, cy + 40)
    image = ImageGrab.grab(bbox=bbox).convert('RGB')
    if user32.GetForegroundWindow() != hwnd:
        raise RuntimeError('Foreground changed during example screen capture')
    return image, width, height, dpi

def capture_windows_picture(color, label):
    image, _, _, _ = capture_windows_region()
    pixels = np.asarray(image)
    if color not in ('red', 'blue'):
        raise ValueError('Unsupported expected color')
    dominant, other = (0, 2) if color == 'red' else (2, 0)
    matches = ((pixels[:, :, dominant] > 150) & (pixels[:, :, 1] < 90) & (pixels[:, :, other] < 90))
    fraction = float(matches.mean())
    if fraction <= 0.85 and label:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', label):
            raise ValueError('Invalid capture label')
        image.save(ROOT / f'{label}-screen.png')
    return {'color': color, 'matching_fraction': fraction,
            'mean_rgb': pixels.mean(axis=(0, 1)).round(1).tolist(), 'passed': fraction > 0.85}

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
    def do_POST(self):
        from urllib.parse import urlparse, parse_qs
        from PIL import Image
        try:
            if urlparse(self.path).path != '/reference-picture':
                raise ValueError('Unknown endpoint')
            query = parse_qs(urlparse(self.path).query)
            label = query['label'][0]
            if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', label):
                raise ValueError('Invalid capture label')
            entry = REFERENCES[label]
            if entry['kind'] != 'reference_video':
                raise ValueError('Not a video reference')
            size = int(self.headers.get('Content-Length', '0'))
            if size <= 0 or size > 5_000_000:
                raise ValueError('Invalid picture size')
            decoded = Image.open(io.BytesIO(self.rfile.read(size))).convert('RGB')
            picture = np.asarray(decoded.resize((96, 54)), dtype=np.int16)
            frames = np.fromfile(entry['reference'], dtype=np.uint8).reshape(-1, 54, 96, 3).astype(np.int16)
            differences = np.abs(frames - picture).mean(axis=(1, 2, 3))
            # A blank frame is not evidence of correctly rendered content.
            differences[frames.std(axis=(1, 2, 3)) < 5] = 255
            difference = float(differences.min())
            video_width = int(query['width'][0])
            video_height = int(query['height'][0])
            if video_width <= 0 or video_height <= 0:
                raise ValueError('Invalid video dimensions')
            screen, client_width, client_height, dpi = capture_windows_region()
            box_width = min(client_width, 640 * dpi / 96)
            box_height = min(client_height, 360 * dpi / 96)
            scale = min(box_width / video_width, box_height / video_height)
            rendered_width, rendered_height = video_width * scale, video_height * scale
            crop_width = min(decoded.width, decoded.width * 80 / rendered_width)
            crop_height = min(decoded.height, decoded.height * 80 / rendered_height)
            crop = decoded.crop(((decoded.width-crop_width)/2, (decoded.height-crop_height)/2,
                                 (decoded.width+crop_width)/2, (decoded.height+crop_height)/2)).resize((80, 80))
            screen_difference = float(np.abs(np.asarray(crop, dtype=np.int16) - np.asarray(screen, dtype=np.int16)).mean())
            report = {'mean_absolute_error': round(difference, 3), 'reference_frame': int(differences.argmin()),
                      'screen_mean_absolute_error': round(screen_difference, 3),
                      'passed': bool(difference < 35 and picture.std() >= 5 and screen_difference < 50)}
            if not report['passed']:
                screen.save(ROOT / f'{label}-screen.png')
                decoded.save(ROOT / f'{label}-snapshot.png')
            (ROOT / f'{label}-picture.json').write_text(json.dumps(report, indent=2))
            self.send_response(200)
            body = json.dumps(report).encode()
        except Exception as error:
            import traceback
            traceback.print_exc()
            self.send_response(500)
            body = json.dumps({'error': str(error)}).encode()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        from urllib.parse import urlparse, parse_qs
        query = parse_qs(urlparse(self.path).query)
        try:
            if urlparse(self.path).path == '/subtitle-picture':
                label = query['label'][0]
                if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', label):
                    raise ValueError('Invalid capture label')
                image, _, _, _ = capture_windows_region((int(query['width'][0]), int(query['height'][0])))
                pixels = np.asarray(image)
                white = np.all(pixels[:, :, :3] > 190, axis=2)
                low = pixels.min(axis=2)
                high = pixels.max(axis=2).astype(np.int16)
                neutral = (low > 35) & ((high - low) < 45)
                red = ((pixels[:, :, 0] > 150) & (pixels[:, :, 1] < 90) & (pixels[:, :, 2] < 90))
                green = ((pixels[:, :, 1] > 120) & (pixels[:, :, 0] < 80) & (pixels[:, :, 2] < 80))
                blue = ((pixels[:, :, 2] > 150) & (pixels[:, :, 0] < 90) & (pixels[:, :, 1] < 90))
                dark_blue = ((pixels[:, :, 2] > 70) & (pixels[:, :, 0] < 70) & (pixels[:, :, 1] < 70))
                non_red = (pixels[:, :, 1] > 90) | (pixels[:, :, 2] > 90)
                gray_background = (low > 35) & (high < 90) & ((high - low) < 8)
                report = {'white_fraction': float(white.mean()), 'white_pixels': int(white.sum()),
                          'neutral_fraction': float(neutral.mean()), 'neutral_pixels': int(neutral.sum()),
                          'red_fraction': float(red.mean()), 'red_pixels': int(red.sum()),
                          'green_fraction': float(green.mean()), 'blue_pixels': int(blue.sum()),
                          'dark_blue_pixels': int(dark_blue.sum()), 'non_red_pixels': int(non_red.sum()),
                          'gray_background_fraction': float(gray_background.mean())}
                reference_name = query.get('palette_reference', [None])[0]
                if reference_name is not None:
                    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', reference_name):
                        raise ValueError('Invalid palette reference label')
                    report.update(compare_palette_reference(image, REFERENCES[reference_name]))
                image.save(ROOT / f'{label}-subtitle.png')
                body = json.dumps(report).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if urlparse(self.path).path == '/picture':
                body = json.dumps(capture_windows_picture(query.get('color', ['red'])[0], query.get('label', [''])[0])).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if urlparse(self.path).path == '/screenshot':
                pixels = capture_android_screen()
                (ROOT / 'android-screen-latest.png').write_bytes(pixels)
                self.send_response(200)
                self.send_header('Content-Type', 'image/png')
                self.send_header('Content-Length', str(len(pixels)))
                self.end_headers()
                self.wfile.write(pixels)
                return
            platform = query['platform'][0]
            label = query['label'][0]
            mode = query.get('mode', [''])[0]
            reference_audio = mode == 'reference'
            frequency = 0 if mode in ('reference', 'stereo', 'downmix_51', 'downmix_71') else int(query['frequency'][0])
            assert platform in ['windows', 'android']
            if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', label):
                raise ValueError('Invalid capture label')
            target = ROOT / f'{platform}-{label}.wav'
            print(f'CAPTURE {platform} {label} expected={frequency}', flush=True)
            discontinuities = 0
            if platform == 'windows':
                # Keep the actual test window visible long enough for inspection.
                # ThreadingHTTPServer creates a new request thread per capture;
                # COM initialization on another thread does not carry over.
                ole32 = ctypes.OleDLL('ole32')
                ole32.CoInitializeEx(None, 0)
                try:
                    time.sleep(args.visual_hold)
                    speaker = sc.default_speaker()
                    loopback = sc.get_microphone(speaker.id, include_loopback=True)
                    data, discontinuities, other_warnings = record_loopback(
                        loopback, sc.SoundcardRuntimeWarning, samplerate=48000,
                        numframes=int(48000 * args.capture_seconds), channels=2)
                    for warning in other_warnings:
                        print(f'CAPTURE WARNING {label}: {warning}', flush=True)
                finally:
                    ole32.CoUninitialize()
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
            rejected = int(query.get('reject_frequency', ['0'])[0])
            rejection_ratio = None
            if rejected > 0 and frequency > 0:
                wanted = float(spectrum[np.abs(freqs-frequency) < 6].max(initial=0))
                unwanted = float(spectrum[np.abs(freqs-rejected) < 6].max(initial=0))
                rejection_ratio = unwanted / wanted if wanted > 0 else None
                passed = passed and rejection_ratio is not None and rejection_ratio < 0.2
            report = dict(platform=platform, label=label, expected_hz=frequency,
                peak_hz=round(peak, 2), rms=round(rms, 7),
                channels_rms=np.sqrt(np.mean(middle**2,axis=0)).round(7).tolist(),
                seconds=round(len(samples)/48000, 2), passed=bool(passed))
            if rejected > 0:
                report.update(reject_frequency=rejected, rejection_ratio=rejection_ratio)
            if reference_audio:
                if REFERENCES[label]['kind'] != 'reference_audio':
                    raise ValueError('Not an audio reference')
                report['expected_hz'] = None
                reference = np.fromfile(REFERENCES[label]['reference'], dtype='<f4')
                report.update(compare_reference_audio(
                    reference, samples, threshold=MIN_REFERENCE_CORRELATION))
            if mode == 'stereo':
                report['expected_hz'] = None
                report.update(compare_stereo_tones(samples, int(query['left'][0]), int(query['right'][0])))
            if mode in ('downmix_51', 'downmix_71'):
                report['expected_hz'] = None
                report.update(compare_surround_downmix(samples, '5.1' if mode == 'downmix_51' else '7.1'))
            if platform == 'windows':
                apply_capture_integrity(report, discontinuities)
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
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

print(f'Audio verification host listening on 127.0.0.1:{args.port}', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
