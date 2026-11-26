# Windows tracker demuxer

This directory contains the Windows VLC 3.0.21 tracker demuxer and a
libopenmpt-based compatibility layer. The demuxer source derives from
[`modules/demux/mod.c`](https://github.com/videolan/vlc/blob/3.0.21/modules/demux/mod.c)
under LGPL-2.1-or-later. The compatibility layer and header come from
libopenmpt-modplug 0.8.9.0-openmpt1, under the included BSD and public-domain
notices. The default noise-reduction filter follows libmodplug's public-domain
`src/snd_dsp.cpp`; filter state is per player and reset on seek.

The demuxer has higher priority than the bundled VLC `mod`
module. VLC can fall back to the original module when libopenmpt rejects a
file, such as an ABC score. The compatibility layer cannot reproduce the
original module's reverb, bass enhancement, or surround effects; when any of
those options is enabled, the OpenMPT module declines the file so VLC
uses the original module. Consequently, files that the original module cannot
decode, including the tested DSMI AMF revision 8 and 9 files, remain unplayable
with those effects enabled. Fallback has not been verified for nonseekable
streams. Noise reduction is applied to the decoded 16-bit stream and is not
claimed to be bit-identical to the original mixer's processing.

To reproduce the DLL, use the x86-64 WinLibs GCC 16.2.0 POSIX
SEH MSVCRT r2 toolchain, the VLC 3.0.21 Windows SDK, and the official
libopenmpt 0.8.9 Windows developer archive, then run:

```powershell
.\tool\build_windows_openmpt.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -OpenMptDevDirectory 'E:\path\to\libopenmpt-dev' `
  -OutputDirectory 'E:\path\to\output'
```

The official libopenmpt archive is
`https://lib.openmpt.org/files/libopenmpt/dev/libopenmpt-0.8.9%2Brelease.dev.windows.vs2022.zip`
with SHA-256 `a23e375e576e3a6997ffeeb6cf34488e9020e2a5d8226856b02628b6a87c5e8e`.
Its dependent libraries' notices are in `licenses/`; the mpg123 component is
LGPL-2.1. The DLL is copied under the private name `vlc_player_openmpt_0_8.dll`
to reduce conflicts with other bundled versions. The resulting module's
checked SHA-256 is
`287ecd6530db89329b3372cd2e27ebb649601c370edc64990e53e80c06950094`.
