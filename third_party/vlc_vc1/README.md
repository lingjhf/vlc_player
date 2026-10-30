# Windows VC-1 elementary-stream demuxer

This module is based on VLC 3.0.21's
[`modules/demux/vc1.c`](https://github.com/videolan/vlc/blob/3.0.21/modules/demux/vc1.c)
and is licensed under LGPL-2.1-or-later; see `COPYING.LGPL-2.1` and the source
notice. The upstream demuxer has priority zero and is only used when explicitly
selected. The modified module has priority 6 and automatically accepts an input
only if its path ends in `.vc1` and its first five bytes contain a VC-1 sequence
start code and advanced-profile marker. Other paths and signatures are left to
the normal VLC demuxers. Explicitly forcing `--demux=vc1` retains upstream
behavior, including its frame-rate handling and support for nonstandard input.
The module also reports its current demux time, allowing playback position to
advance for elementary streams; it does not add seeking or duration support.

This conservative probe does not identify every possible VC-1 input. In
particular, streams with leading data before their sequence header remain
unverified. Decoder support and correct rendering still depend on the stream.

The binary is built with stack protection and statically linked GCC libssp;
its source and license notices are included in `../vlc_mmdevice`. To reproduce
it, use the x86-64 WinLibs GCC 16.2.0 POSIX SEH MSVCRT r2 toolchain and the
official VLC 3.0.21 Windows SDK:

```powershell
.\tool\build_windows_vc1.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -OutputDirectory 'E:\path\to\output'
```

The WinLibs release archive has SHA-256
`72b0a8e1ba1836d8fc0f12e54695a8708985cc3ea375fd954d9ebd328f842a9c`.
The resulting module has SHA-256
`35041c27e49932f559812063f148a6784d0e0c82a6d9d9279d3bfa48d72d3d55`.
