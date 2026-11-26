# Windows MMDevice audio output

This directory contains a modified VLC 3.0.21 MMDevice audio-output module
and its reproducible x64 Windows binary. The upstream source is
[`modules/audio_output/mmdevice.c` and `mmdevice.h`](https://github.com/videolan/vlc/tree/3.0.21/modules/audio_output),
with [`vlc_memory.h`](https://github.com/videolan/vlc/blob/3.0.21/include/vlc_memory.h)
from the same release. The module is licensed under LGPL-2.1-or-later; see
`COPYING.LGPL-2.1` and the notices in the source files.

The original MMDevice module can put simultaneous players in the same Windows
audio session, so changing one player's volume or mute changes the other. This
version allocates the lowest available process-local session slot for each
live audio output and uses its GUID for both session control and the output
stream. Slots are released when an output closes and reused, avoiding a new
persistent Windows session for every player recreation. Windows may retain
the settings associated with a slot, so a later player reusing it can inherit
those settings. Device selection and notification remain the upstream
MMDevice implementation. Physical audio-device hot-plug has not been tested.

The module is compiled with stack protection and statically linked GCC libssp.
The GCC 16.2.0 `libssp` sources used for that runtime are included here with
their notices, together with `COPYING.GPL-3` and `COPYING.RUNTIME`. The source
files are also available in the [GCC 16.2.0 release](https://github.com/gcc-mirror/gcc/tree/releases/gcc-16.2.0/libssp).

To reproduce `bin/x64/libmmdevice_plugin.dll`, use the x86-64 WinLibs GCC
16.2.0 POSIX SEH MSVCRT r2 toolchain and the SDK from the official VLC 3.0.21
Windows x64 archive, then run from the repository root:

```powershell
.\tool\build_windows_mmdevice.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -OutputDirectory 'E:\path\to\output'
```

The WinLibs release archive used for this build has SHA-256
`72b0a8e1ba1836d8fc0f12e54695a8708985cc3ea375fd954d9ebd328f842a9c`.
The resulting DLL has SHA-256
`0d5b36ad46e68bdfb3a772c21169f1fc2f0d3fc64f8819e0794295b4ef5791a9`;
the script checks this value. The fixed PE image base and omitted build
timestamp make the result independent of the output directory; ASLR remains
enabled. The normal application build verifies and copies this binary and does
not require the compiler.
