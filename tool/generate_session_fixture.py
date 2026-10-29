"""Generate the deterministic session playback fixture using FFmpeg."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ffmpeg', default='ffmpeg')
args = parser.parse_args()
output = Path(__file__).resolve().parents[1] / 'example/assets/format_fixtures/session_av.mp4'
subprocess.run([
    args.ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
    '-f', 'lavfi', '-i', 'color=c=red:s=320x180:r=15:d=16',
    '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:r=15:d=16',
    '-f', 'lavfi', '-i',
    r'aevalsrc=0.125*sin(2*PI*if(lt(t\,16)\,440\,880)*t):s=48000:d=32',
    '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0[v]',
    '-map', '[v]', '-map', '2:a', '-c:v', 'libx264', '-profile:v', 'baseline',
    '-pix_fmt', 'yuv420p', '-g', '15', '-c:a', 'aac', '-b:a', '96k', '-ac', '2',
    '-movflags', '+faststart', str(output),
], check=True)
print(output)
