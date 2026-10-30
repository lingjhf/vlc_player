# Windows Shorten demuxer

VLC's FFmpeg demuxer does not provide timestamps for raw Shorten streams. The
Windows plugin installs this module, which decodes the
stream to PCM and derives timestamps from the decoded sample count, allowing
VLC's audio output to pace playback. The demuxer source is LGPL-2.1-or-later.

The module statically links a minimal LGPL build of FFmpeg 8.1.2. The included
patch exposes the Shorten stream's embedded WAVE or AIFF header so that the
module can read its duration and account for the AIFF SSND prefix. The
standalone demux object is retained alongside the DLL so it can be relinked
with a modified compatible FFmpeg build. FFmpeg source is available from
[VideoLAN](https://download.videolan.org/pub/contrib/ffmpeg/ffmpeg-8.1.2.tar.xz);
its SHA-256 is
`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`.
The FFmpeg and demuxer license is in `COPYING.LGPL-2.1`. The binary also
statically includes winpthreads, whose notices are in `COPYING.winpthreads`,
and the GCC stack-protection runtime, whose sources and notices are included
in `../vlc_mmdevice`.

To build with WinLibs GCC 16.2.0 MSVCRT POSIX SEH r2, Git Bash, an unmodified
FFmpeg 8.1.2 source tree, and VLC 3.0.21 source and Windows SDK:

```powershell
.\tool\build_windows_shorten.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -MakePath 'E:\path\to\mingw64\bin\mingw32-make.exe' `
  -BashPath 'C:\Program Files\Git\bin\bash.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-sdk' `
  -VlcSourceDirectory 'E:\path\to\vlc-source' `
  -FfmpegSourceDirectory 'E:\path\to\ffmpeg-8.1.2' `
  -OutputDirectory 'E:\path\to\new-output'
```

The output directory must not contain whitespace or be inside the FFmpeg
source tree. The script copies the source there and does not modify the input
tree. Use a fresh output directory for each build. The candidate DLL SHA-256 is
`6b7bb4fdba4f468c6d4609e34dd87316fc0371d2443d616d2d3236a5f1990784`;
the corresponding demux object SHA-256 is
`3cdb7d4865b5a63f895db2d70dac2c45b126f054697cf7b039c28539fc6a2d0c`.
Both were reproduced using different FFmpeg source and build directories.

Known limitations still requiring validation include real non-buffered live
streams, uncommon AIFF-C compression tags, multichannel AIFF ordering,
unusual sample rates, long-distance seeks on slow storage, and malformed input.
Seek currently decodes from the beginning, so its latency grows with the seek
position. WAVE files without a channel mask use VLC's default WAVE ordering.
