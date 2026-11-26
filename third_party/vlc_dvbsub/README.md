# Windows DVB subtitle decoder

This directory contains a modified VLC 3.0.21 DVB subtitle module and its
reproducible x64 Windows binary. The upstream source is
[`modules/codec/dvbsub.c`](https://github.com/videolan/vlc/blob/3.0.21/modules/codec/dvbsub.c).
The module is licensed under LGPL-2.1-or-later; see `COPYING.LGPL-2.1` and the
source notice.

The decoder now initializes the 2-, 4-, and 8-bit default color lookup tables
and uses them when a region references a CLUT that has not been received.
Explicit CLUT definitions still take precedence. This follows the default
tables in section 10 of [ETSI EN 300 743](https://www.etsi.org/deliver/etsi_en/300700_300799/300743/01.06.01_60/en_300743v010601p.pdf).
If a stream has lost a custom CLUT, the default colors cannot recover the
missing original colors, but can make its subtitle content visible.

The module retains VLC's subtitle encoder and is compiled with stack
protection and statically linked GCC libssp. The GCC runtime source and license
notices are included in [`../vlc_mmdevice`](../vlc_mmdevice/README.md).

To reproduce `bin/x64/libdvbsub_plugin.dll`, use the x86-64 WinLibs GCC
16.2.0 POSIX SEH MSVCRT r2 toolchain and the SDK from the official VLC 3.0.21
Windows x64 archive, then run from the repository root:

```powershell
.\tool\build_windows_dvbsub.ps1 `
  -GccPath 'E:\path\to\mingw64\bin\gcc.exe' `
  -VlcSdkDirectory 'E:\path\to\vlc-3.0.21\sdk' `
  -OutputDirectory 'E:\path\to\output'
```

The WinLibs release archive used for this build has SHA-256
`72b0a8e1ba1836d8fc0f12e54695a8708985cc3ea375fd954d9ebd328f842a9c`.
The resulting DLL has SHA-256
`1d34ca937959ab874729fd59f0d2131eccab3c743b03677d6eeab6729d1252f6`;
the script checks this value. The fixed PE image base and omitted build
timestamp make the result independent of the output directory; ASLR remains
enabled. The normal application build verifies and copies the binary without
requiring the compiler.
