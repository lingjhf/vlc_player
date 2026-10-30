# Windows PVA demuxer

This module is based on VLC 3.0.21's
[`modules/demux/pva.c`](https://github.com/videolan/vlc/blob/3.0.21/modules/demux/pva.c)
and is licensed under LGPL-2.1-or-later. See `COPYING.LGPL-2.1` and the
source notice. It reports a relative playback time from the timestamps used
for the demuxer's PCR, switching from the video clock to the audio clock when
the latter becomes available. It preserves elapsed time when audio arrives
later and adjusts the origin if the first audio timestamp is earlier than the
first video timestamp; PVA files can begin with a large nonzero timestamp.

The 32-bit PVA video clock wraps. The relative clock unwraps consecutive
timestamps, including backward jumps used by the existing position seek.
Video timestamps are also unwrapped for decoding and aligned with audio when
it becomes available, avoiding a frozen picture at a 32-bit wrap.
It assumes a timestamp jump spans less than half a 32-bit clock cycle (about
6.6 hours). This module does not add duration estimation or time-based seek;
VLC's existing byte-position seek remains available. Time is based on the
demuxer's timestamps and can lead the displayed frame due to buffering. Audio
33-bit timestamp rollover and very large discontinuities are not verified.

The upstream PES parser was also guarded against short headers; the timestamp
calculation for complete headers remains the same as VLC 3.0.21. The binary
uses stack protection and statically linked GCC libssp, whose source and
license notices are included in `../vlc_mmdevice`.

To reproduce the module, use the x86-64 WinLibs GCC 16.2.0 POSIX SEH MSVCRT
r2 toolchain and the official VLC 3.0.21 Windows SDK:

```powershell
.\tool\build_windows_pva.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -OutputDirectory 'E:\path\to\output'
```

The WinLibs release archive has SHA-256
`72b0a8e1ba1836d8fc0f12e54695a8708985cc3ea375fd954d9ebd328f842a9c`.
The resulting module has SHA-256
`8985ac57bd54652a77c6efc28ff724699524117c1e41cb50ad0b96ec095129ed`.
