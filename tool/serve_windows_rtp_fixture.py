"""Publish a local RTP/MPEG-TS fixture until a test requests disconnect.

The control directory must be new or empty: this program never removes an
existing trigger. FFmpeg's diagnostic output and control files stay there.
"""
import argparse
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--control-dir', type=Path, required=True)
    parser.add_argument('--port', type=int, default=12346)
    args = parser.parse_args()
    root = args.control_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    trigger, ack = root / 'disconnect.trigger', root / 'disconnect.done'
    if trigger.exists() or ack.exists():
        raise SystemExit('Control files already exist; choose a fresh control directory.')
    command = [args.ffmpeg, '-hide_banner', '-loglevel', 'warning', '-nostdin',
               '-re', '-f', 'lavfi', '-i', 'color=c=red:s=352x288:r=25',
               '-re', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
               '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency',
               '-g', '25', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
               '-f', 'rtp_mpegts', f'rtp://127.0.0.1:{args.port}?pkt_size=1316']
    with (root / 'publisher.log').open('wb') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            print(f'RTP publisher started (pid {process.pid})', flush=True)
            while not trigger.exists():
                if process.poll() is not None:
                    raise RuntimeError(f'Publisher exited early: {process.returncode}')
                time.sleep(.1)
            process.terminate()
            process.wait(timeout=10)
            ack.write_text('publisher stopped\n', encoding='utf-8')
            print('RTP publisher stopped on request', flush=True)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)


if __name__ == '__main__':
    main()
