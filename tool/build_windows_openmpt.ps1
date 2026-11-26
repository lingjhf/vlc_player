param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$OpenMptDevDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\third_party\vlc_openmpt')).Path
$gcc = (Resolve-Path -LiteralPath $GccPath).Path
$sdk = (Resolve-Path -LiteralPath $VlcSdkDirectory).Path
$openmpt = (Resolve-Path -LiteralPath $OpenMptDevDirectory).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ((& $gcc -dumpfullversion).Trim() -ne '16.2.0' -or
    ((& $gcc --version | Select-Object -First 1) -notmatch 'x86_64-msvcrt-posix-seh.*r2')) {
  throw 'Expected the documented WinLibs GCC 16.2.0 MSVCRT r2 toolchain.'
}
$env:PATH = (Split-Path -Parent $gcc) + [IO.Path]::PathSeparator + $env:PATH
Push-Location $source
try {
  & $gcc -std=gnu11 -O2 -fstack-protector-strong -DMODPLUG_STATIC -D__PLUGIN__ `
    -D_FILE_OFFSET_BITS=64 -D_REENTRANT -D_THREAD_SAFE -D__MSVCRT_VERSION__=0x0700 `
    -I "$sdk\include\vlc\plugins" -I . -include prelude.h `
    -c openmptmod.c -o "$out\openmptmod.o"
  if ($LASTEXITCODE -ne 0) { throw 'VLC demux compilation failed.' }
  & $gcc -std=gnu11 -O2 -fstack-protector-strong -I "$openmpt\inc" -I . `
    -c libopenmpt_modplug.c -o "$out\compat.o"
  if ($LASTEXITCODE -ne 0) { throw 'OpenMPT compatibility compilation failed.' }
  $dlltool = Join-Path (Split-Path -Parent $gcc) 'dlltool.exe'
  Push-Location $out
  try {
    & $dlltool -m i386:x86-64 -d "$source\openmpt.def" -l openmpt-import.a
    if ($LASTEXITCODE -ne 0) { throw 'OpenMPT import library generation failed.' }
  } finally {
    Pop-Location
  }
  & $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' `
    "$out\openmptmod.o" "$out\compat.o" "$sdk\lib\libvlccore.lib" `
    "$out\openmpt-import.a" '-Wl,-Bstatic' -lssp '-Wl,-Bdynamic' `
    -o "$out\libopenmptmod_plugin.dll"
  if ($LASTEXITCODE -ne 0) { throw 'OpenMPT module linking failed.' }
} finally {
  Pop-Location
}
$actual = (Get-FileHash -LiteralPath "$out\libopenmptmod_plugin.dll" -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = '287ecd6530db89329b3372cd2e27ebb649601c370edc64990e53e80c06950094'
if ($actual -ne $expected) { throw "Build produced SHA-256 $actual; expected $expected." }
Write-Output "Reproduced $out\libopenmptmod_plugin.dll (SHA-256 $actual)"
