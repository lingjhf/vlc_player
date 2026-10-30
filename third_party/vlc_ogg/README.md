# Windows Ogg demuxer

This module is based on VLC 3.0.21's Ogg demuxer and is licensed under
LGPL-2.1-or-later; see `COPYING.LGPL-2.1` and the source notices. For OggDS
text subtitles, a positive granule position represents the current subtitle
packet's timestamp. The upstream module instead uses the previous packet's
granule, causing cues to start too early. The modification uses the current
granule for these subtitles, as the demuxer already does for OggDS video.
Other codec branches retain upstream timing behavior. Packets without a
granule position continue to use upstream interpolation; multi-packet subtitle
pages and every OGM variant have not been validated.

The binary statically includes libogg 1.3.3 and libvorbis 1.3.6. Their
BSD-style license notices are in `COPYING.libogg` and `COPYING.libvorbis`.
It also contains the GCC stack-protection runtime; its source and license
notices are included in `../vlc_mmdevice`. `fixups.c` provides the formatted
string and bounded duplication functions needed by the MSVCRT toolchain.

To reproduce the module, use the x86-64 WinLibs GCC 16.2.0 POSIX SEH MSVCRT
r2 toolchain, the official VLC 3.0.21 Windows SDK and source, and the libogg
1.3.3 and libvorbis 1.3.6 source archives:

```powershell
.\tool\build_windows_ogg.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -VlcSourceDirectory 'E:\path\to\vlc-3.0.21' `
  -OggSourceDirectory 'E:\path\to\libogg-1.3.3' `
  -VorbisSourceDirectory 'E:\path\to\libvorbis-1.3.6' `
  -OutputDirectory 'E:\path\to\output'
```

The source archives are available from [VideoLAN](https://download.videolan.org/pub/videolan/vlc/3.0.21/vlc-3.0.21.tar.xz),
[Xiph libogg](https://downloads.xiph.org/releases/ogg/libogg-1.3.3.tar.xz),
and [Xiph libvorbis](https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.6.tar.xz).
The VLC source archive SHA-256 is
`24dbbe1d7dfaeea0994d5def0bbde200177347136dbfe573f5b6a4cee25afbb0`.
VLC's contrib source checksums specify SHA-512 values
`37d8e4329bf7a997a95d84a55c325a5a893ec84bb4d5b7ea638e5cb13201a0619e71ecd9710a8371def69f092c62dcc59ec0a607db246028ee8a62678386260b`
for libogg and
`a5d990bb88db2501b16f8eaee9f2ecb599cefd7dab2134d16538d8905263a972157c7671867848c2a8a358bf5e5dbc7721205ece001032482f168be7bda4f132`
for libvorbis. The WinLibs archive SHA-256 is
`72b0a8e1ba1836d8fc0f12e54695a8708985cc3ea375fd954d9ebd328f842a9c`.
The resulting module SHA-256 is
`705b091683075d7aac22ef04c42bc3d5239a8b69f54c43df9cea8d87a2de9d09`.
