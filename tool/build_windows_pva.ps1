param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\third_party\vlc_pva')).Path
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
    -c pva-time.c -o "$out\pva-time.o"
  if ($LASTEXITCODE -ne 0) { throw 'PVA demux compilation failed.' }
  & $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' `
    "$out\pva-time.o" "$sdk\lib\libvlccore.lib" '-Wl,-Bstatic' -lssp '-Wl,-Bdynamic' `
    -o "$out\libpva_plugin.dll"
  if ($LASTEXITCODE -ne 0) { throw 'PVA demux linking failed.' }
} finally {
  Pop-Location
}
$actual = (Get-FileHash -LiteralPath "$out\libpva_plugin.dll" -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = '8985ac57bd54652a77c6efc28ff724699524117c1e41cb50ad0b96ec095129ed'
if ($actual -ne $expected) { throw "Build produced SHA-256 $actual; expected $expected." }
Write-Output "Reproduced $out\libpva_plugin.dll (SHA-256 $actual)"
