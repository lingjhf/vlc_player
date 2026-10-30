param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\third_party\vlc_vc1')).Path
$gcc = (Resolve-Path -LiteralPath $GccPath).Path
$sdk = (Resolve-Path -LiteralPath $VlcSdkDirectory).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ((& $gcc -dumpfullversion).Trim() -ne '16.2.0' -or
    ((& $gcc --version | Select-Object -First 1) -notmatch 'x86_64-msvcrt-posix-seh.*r2')) {
  throw 'Expected the documented WinLibs GCC 16.2.0 MSVCRT r2 toolchain.'
}
$env:PATH = (Split-Path -Parent $gcc) + [IO.Path]::PathSeparator + $env:PATH
Push-Location $source
try {
  & $gcc -std=gnu11 -O2 -fstack-protector-strong -D__PLUGIN__ `
    -D_FILE_OFFSET_BITS=64 -D_REENTRANT -D_THREAD_SAFE -D__MSVCRT_VERSION__=0x0700 `
    -I "$sdk\include\vlc\plugins" -I . -include prelude.h `
    -c vc1-auto.c -o "$out\vc1-auto.o"
  if ($LASTEXITCODE -ne 0) { throw 'VC-1 demux compilation failed.' }
  & $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' `
    "$out\vc1-auto.o" "$sdk\lib\libvlccore.lib" '-Wl,-Bstatic' -lssp '-Wl,-Bdynamic' `
    -o "$out\libvc1_plugin.dll"
  if ($LASTEXITCODE -ne 0) { throw 'VC-1 demux linking failed.' }
} finally {
  Pop-Location
}
$actual = (Get-FileHash -LiteralPath "$out\libvc1_plugin.dll" -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = '35041c27e49932f559812063f148a6784d0e0c82a6d9d9279d3bfa48d72d3d55'
if ($actual -ne $expected) { throw "Build produced SHA-256 $actual; expected $expected." }
Write-Output "Reproduced $out\libvc1_plugin.dll (SHA-256 $actual)"
