param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$MakePath,
  [Parameter(Mandatory = $true)][string]$BashPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$VlcSourceDirectory,
  [Parameter(Mandatory = $true)][string]$FfmpegSourceDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$module = (Resolve-Path (Join-Path $PSScriptRoot '..\third_party\vlc_shorten')).Path
$gcc = (Resolve-Path -LiteralPath $GccPath).Path
$make = (Resolve-Path -LiteralPath $MakePath).Path
$bash = (Resolve-Path -LiteralPath $BashPath).Path
$sdk = (Resolve-Path -LiteralPath $VlcSdkDirectory).Path
$vlc = (Resolve-Path -LiteralPath $VlcSourceDirectory).Path
$ffmpeg = (Resolve-Path -LiteralPath $FfmpegSourceDirectory).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ($out -match '\s') {
  throw 'The output path must not contain whitespace.'
}
if ($out.Equals($ffmpeg, [StringComparison]::OrdinalIgnoreCase) -or
    $out.StartsWith($ffmpeg.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The output directory must not be inside the FFmpeg source directory.'
}
if (Get-ChildItem -LiteralPath $out -Force | Select-Object -First 1) {
  throw 'The output directory must be empty.'
}
if ((& $gcc -dumpfullversion).Trim() -ne '16.2.0' -or
    ((& $gcc --version | Select-Object -First 1) -notmatch 'x86_64-msvcrt-posix-seh.*r2')) {
  throw 'Expected the documented WinLibs GCC 16.2.0 MSVCRT r2 toolchain.'
}
$copy = Join-Path $out 'ffmpeg-source'
$build = Join-Path $out 'ffmpeg-build'
$makeDir = Join-Path $out 'tools'
if (Test-Path -LiteralPath $copy -PathType Any) {
  throw "Build source copy already exists: $copy. Use a fresh output directory."
}
if (Test-Path -LiteralPath $build -PathType Any) {
  throw "Build directory already exists: $build. Use a fresh output directory."
}
Copy-Item -LiteralPath $ffmpeg -Destination $copy -Recurse
New-Item -ItemType Directory -Path $build, $makeDir -Force | Out-Null
Copy-Item -LiteralPath $make -Destination (Join-Path $makeDir 'make.exe')
& git -C $copy apply --check (Join-Path $module 'ffmpeg-shorten-header.patch')
if ($LASTEXITCODE -ne 0) { throw 'The FFmpeg source is incompatible or already patched.' }
& git -C $copy apply (Join-Path $module 'ffmpeg-shorten-header.patch')
if ($LASTEXITCODE -ne 0) { throw 'Applying the FFmpeg Shorten patch failed.' }

$variables = @('VLC_SHORTEN_SOURCE', 'VLC_SHORTEN_BUILD', 'VLC_SHORTEN_MAKE_DIR', 'VLC_SHORTEN_GCC_DIR', 'PATH')
$previous = @{}
foreach ($name in $variables) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
$env:VLC_SHORTEN_SOURCE = $copy
$env:VLC_SHORTEN_BUILD = $build
$env:VLC_SHORTEN_MAKE_DIR = $makeDir
$env:VLC_SHORTEN_GCC_DIR = Split-Path -Parent $gcc
$configureScript = @'
set -eu
src=$(cygpath -u "$VLC_SHORTEN_SOURCE")
build=$(cygpath -u "$VLC_SHORTEN_BUILD")
tools=$(cygpath -u "$VLC_SHORTEN_MAKE_DIR")
gcc=$(cygpath -u "$VLC_SHORTEN_GCC_DIR")
export PATH="$tools:$gcc:$PATH"
cd "$build"
"$src/configure" --disable-everything --enable-decoder=shorten --disable-programs --disable-doc --disable-debug --disable-avformat --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample --disable-network --disable-pthreads --enable-w32threads --disable-autodetect --disable-x86asm --disable-shared --enable-static --enable-small --target-os=mingw32 --arch=x86_64 --cc=gcc --ar=ar --ranlib=ranlib --extra-cflags=-fstack-protector-strong
'@
$configureFile = Join-Path $out 'configure-shorten.sh'
[IO.File]::WriteAllText($configureFile, $configureScript.Replace("`r`n", "`n"))
& $bash $configureFile
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg configuration failed.' }
$sourceUnix = (& $bash -c 'cygpath -u "$VLC_SHORTEN_SOURCE"').Trim()
if ($LASTEXITCODE -ne 0 -or !$sourceUnix) { throw 'Could not convert the source path.' }
$sourceWin = $copy.Replace('\', '/')
$buildWin = $build.Replace('\', '/')
foreach ($file in @((Join-Path $build 'Makefile'), (Join-Path $build 'ffbuild\config.mak'))) {
  $text = [IO.File]::ReadAllText($file)
  if (!$text.Contains($sourceUnix)) { throw "FFmpeg source path missing from $file." }
  $text = $text.Replace($sourceUnix, $sourceWin)
  if ($file.EndsWith('config.mak')) {
    if (!$text.Contains("`nCFLAGS=")) { throw 'FFmpeg CFLAGS are missing.' }
    $text = $text.Replace("`nCFLAGS=", "`nCFLAGS= -ffile-prefix-map=$sourceWin=ffmpeg -ffile-prefix-map=$buildWin=build ")
  }
  [IO.File]::WriteAllText($file, $text)
}
$makeScript = @'
set -eu
tools=$(cygpath -u "$VLC_SHORTEN_MAKE_DIR")
gcc=$(cygpath -u "$VLC_SHORTEN_GCC_DIR")
export PATH="$tools:$gcc:$PATH"
cd "$(cygpath -u "$VLC_SHORTEN_BUILD")"
make -j4
'@
$makeFile = Join-Path $out 'make-shorten.sh'
[IO.File]::WriteAllText($makeFile, $makeScript.Replace("`r`n", "`n"))
& $bash $makeFile
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg compilation failed.' }

$env:PATH = (Split-Path -Parent $gcc) + [IO.Path]::PathSeparator + $env:PATH
$object = Join-Path $out 'shorten-demux.o'
$dll = Join-Path $out 'libshorten_plugin.dll'
& $gcc -std=gnu11 -O2 -fstack-protector-strong -D__PLUGIN__ '-frandom-seed=vlc-shorten' `
  "-ffile-prefix-map=$module=vlc_shorten" -include "$module\prelude.h" `
  -I "$vlc\include" -I $build -I $copy -c "$module\shorten.c" -o $object
if ($LASTEXITCODE -ne 0) { throw 'Shorten demux compilation failed.' }
& $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' `
  $object "$build\libavcodec\libavcodec.a" "$build\libavutil\libavutil.a" `
  "$sdk\lib\libvlccore.lib" '-Wl,-Bstatic' -lssp -lwinpthread '-Wl,-Bdynamic' `
  -lm -latomic -lole32 -luser32 -lbcrypt -o $dll
if ($LASTEXITCODE -ne 0) { throw 'Shorten module linking failed.' }
Write-Output "Built $dll (SHA-256 $((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()))"
} finally {
  foreach ($name in $variables) {
    [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
  }
}
