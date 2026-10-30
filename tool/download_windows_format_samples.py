"""Download public FFmpeg samples missing from the synthetic encoder matrix.

Files remain in the requested external directory, with URL and SHA-256 recorded.
The FFmpeg sample archive includes malformed files; being downloadable does not
by itself establish that a sample is valid or that VLC supports its profile.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import time
from urllib.parse import quote
from urllib.request import Request, urlopen


SAMPLES = {
    'rv10': 'real/VC-RV10/dannie-56.rm',
    'rv20': 'real/VC-RV20/circuitnomusume.rm',
    'rv30': 'real/VC-RV30/sample.rm',
    'rv40': 'real/VC-RV40/20040506.rm',
    'vp3': 'V-codecs/VP3/vp31.avi',
    'vp5': 'V-codecs/VP5/vp5_interlace.avi',
    'vp5_alternate': 'V-codecs/VP5/potter512-400.avi',
    'vp6': 'V-codecs/VP6/predator2_vp60.avi',
    'vc1': 'V-codecs/WVC1/rtvc1.vc1',
    'vc1_truehd_m2ts': 'A-codecs/TrueHD/vc1-with-truehd.m2ts',
    'vc1_wmv': 'V-codecs/WVC1/Test_1440x576_WVC1_6Mbps.wmv',
    'atrac3': 'A-codecs/ATRAC3/mc_sich_at3_066.wav',
    'ape': 'A-codecs/lossless/luckynight.ape',
    'mace3': 'A-codecs/MACE/surge-samples/surge-1-8-MAC3.mov',
    'mace6': 'A-codecs/MACE/surge-samples/surge-1-8-MAC6.mov',
    'musepack': 'A-codecs/musepack/sv8/musepack_sv8.mpc',
    'qcelp': 'A-codecs/qcp/qcpclip.qcp',
    'qdm2': 'A-codecs/QDM2/startupsound.mov',
    'qdmc': 'A-codecs/QDMC/rumcoke.mov',
    'wmapro': 'A-codecs/WMA9/wma_0x163.wma',
    'mp1': 'A-codecs/mp1-sample.mp1',
    'h261': 'V-codecs/h261/h261test.avi',
    'indeo3': 'V-codecs/IV32/indeo32.avi',
    'sorenson1': 'V-codecs/SVQ1/101.mov',
    'sorenson3': 'V-codecs/SVQ3/gl2.mov',
    'sorenson3_alternate': 'V-codecs/SVQ3/shrek2_tsr_qt_240.mov',
    'dv': 'DV-raw/small_test2.dv',
    'mxf': 'MXF/ebu_small.mxf',
    'pva': 'PVA/PVA_test.pva',
    'vob': 'MPEG-VOB/LPCM/lpcm.vob',
    'voc': 'voc/pcm_u8_1/30smthg1.voc',
    'dirac': 'V-codecs/Dirac/RL_420p_ffdirac.drc',
    'mlp': 'A-codecs/lossless/mlp/440hz.mlp',
    'truehd': 'ffmpeg-bugs/trac/ticket1726/Mono.thd',
    'wma_pro': 'A-codecs/WMA9/WMAPro_5dot1/ambient1_192_mulitchannel.wma',
    'real_sipr': 'real/AC-sipr/intro.rm',
    'ogm': 'archive/extension/ogm/ogg+mpeg4+vorbis+0x0000+ogm_remux.ogm',
    'shorten': 'A-codecs/lossless/luckynight.shn',
    'mpeg4_als': 'A-codecs/lossless/luckynight-als.mp4',
    'dts_96_24': 'A-codecs/DTS/dts/96-24.dts',
    'dtshd_ma_stereo': 'A-codecs/DTS/dts/Master Audio 2.0 16bit.dts',
    'dtshd_ma_51': 'A-codecs/DTS/dts/Master Audio 5.1 24bit.dts',
    'dtshd_hra_51': 'A-codecs/DTS/dts/Hi-Res 5.1 24bit.dts',
    'wmv3_simple': 'V-codecs/WMV9/wmv-samples/sample-wmv9-simple-SP@ML.wmv',
    'wmv3_main': 'V-codecs/WMV9/wmv-samples/sample-wmv9-main-MP@LL.wmv',
    'wmv3_complex': 'V-codecs/WMV9/wmv-samples/sample-wmv9-complex-CP.wmv',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--max-bytes', type=int, default=50_000_000)
    parser.add_argument('--max-seconds', type=float, default=180,
                        help='Download deadline per sample (default: 180 seconds).')
    parser.add_argument('--only', nargs='+', choices=SAMPLES.keys())
    args = parser.parse_args()
    if args.max_bytes <= 0 or args.max_seconds <= 0:
        parser.error('--max-bytes and --max-seconds must be positive')
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)

    def download(item):
        name, relative = item
        url = 'https://samples.ffmpeg.org/' + quote(relative, safe='/')
        target = root / (name + Path(relative).suffix.lower())
        result = {'name': name, 'url': url, 'path': str(target)}
        try:
            deadline = time.monotonic() + args.max_seconds
            request = Request(url, headers={'User-Agent': 'vlc-player-format-validation/1.0'})
            with urlopen(request, timeout=min(30, args.max_seconds)) as response:
                length = response.headers.get('Content-Length')
                if length is not None and int(length) > args.max_bytes:
                    raise ValueError(f'File exceeds limit: {length} bytes')
                digest = hashlib.sha256()
                size = 0
                temporary = target.with_suffix(target.suffix + '.partial')
                try:
                    with temporary.open('wb') as output:
                        while chunk := response.read1(64 * 1024):
                            if time.monotonic() > deadline:
                                raise TimeoutError(f'Download exceeded {args.max_seconds} seconds')
                            size += len(chunk)
                            if size > args.max_bytes:
                                raise ValueError(f'File exceeds limit: {size} bytes')
                            digest.update(chunk)
                            output.write(chunk)
                    if length is not None and size != int(length):
                        raise ValueError(f'Truncated: {size} of {length} bytes')
                    temporary.replace(target)
                finally:
                    temporary.unlink(missing_ok=True)
            result.update(size=size, sha256=digest.hexdigest(), status='downloaded')
        except Exception as error:
            result.update(status='failed', error=str(error))
        return result

    results = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(download, item) for item in SAMPLES.items()
                   if args.only is None or item[0] in args.only]
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            print(result['name'], result['status'], result.get('error', ''), flush=True)
    (root / 'downloads.json').write_text(json.dumps(sorted(results, key=lambda x: x['name']), indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
