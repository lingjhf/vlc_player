param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$sourceDirectory = Join-Path $PSScriptRoot '..\third_party\vlc_dvbsub'
$gcc = (Resolve-Path -LiteralPath $GccPath).Path
$sdk = (Resolve-Path -LiteralPath $VlcSdkDirectory).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
$compilerVersion = (& $gcc -dumpfullversion).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerVersion -ne '16.2.0') {
  throw "Expected GCC 16.2.0; found '$compilerVersion'."
}
$compilerInfo = (& $gcc --version | Select-Object -First 1)
if ($compilerInfo -notmatch 'x86_64-msvcrt-posix-seh.*r2') {
  throw "Expected the documented WinLibs MSVCRT toolchain; found '$compilerInfo'."
}
$env:PATH = (Split-Path -Parent $gcc) + [IO.Path]::PathSeparator + $env:PATH
$object = Join-Path $out 'dvbsub.o'
$library = Join-Path $out 'libdvbsub_plugin.dll'
$headers = Join-Path $sdk 'include\vlc\plugins'
$coreImport = Join-Path $sdk 'lib\libvlccore.lib'
Push-Location $sourceDirectory
try {
  & $gcc -std=gnu11 -O2 -fstack-protector-strong -D__PLUGIN__ -DENABLE_SOUT=1 `
    -D_FILE_OFFSET_BITS=64 -D_REENTRANT -D_THREAD_SAFE -D__MSVCRT_VERSION__=0x0700 `
    -I $headers -I . -include prelude.h -c dvbsub-default.c -o $object
  if ($LASTEXITCODE -ne 0) { throw 'DVB subtitle compilation failed.' }
  & $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' $object $coreImport `
    '-Wl,-Bstatic' -lssp '-Wl,-Bdynamic' -o $library
  if ($LASTEXITCODE -ne 0) { throw 'DVB subtitle linking failed.' }
} finally {
  Pop-Location
}
$actualHash = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedHash = '1d34ca937959ab874729fd59f0d2131eccab3c743b03677d6eeab6729d1252f6'
if ($actualHash -ne $expectedHash) {
  throw "Build produced SHA-256 $actualHash rather than the checked-in binary's hash."
}
Write-Output "Reproduced $library (SHA-256 $actualHash)"
