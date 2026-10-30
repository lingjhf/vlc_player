param(
  [Parameter(Mandatory = $true)][string]$GccPath,
  [Parameter(Mandatory = $true)][string]$VlcSdkDirectory,
  [Parameter(Mandatory = $true)][string]$VlcSourceDirectory,
  [Parameter(Mandatory = $true)][string]$OggSourceDirectory,
  [Parameter(Mandatory = $true)][string]$VorbisSourceDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$module = (Resolve-Path (Join-Path $PSScriptRoot '..\third_party\vlc_ogg')).Path
$gcc = (Resolve-Path -LiteralPath $GccPath).Path
$sdk = (Resolve-Path -LiteralPath $VlcSdkDirectory).Path
$vlc = (Resolve-Path -LiteralPath $VlcSourceDirectory).Path
$ogg = (Resolve-Path -LiteralPath $OggSourceDirectory).Path
$vorbis = (Resolve-Path -LiteralPath $VorbisSourceDirectory).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ((& $gcc -dumpfullversion).Trim() -ne '16.2.0' -or
    ((& $gcc --version | Select-Object -First 1) -notmatch 'x86_64-msvcrt-posix-seh.*r2')) {
  throw 'Expected the documented WinLibs GCC 16.2.0 MSVCRT r2 toolchain.'
}
$env:PATH = (Split-Path -Parent $gcc) + [IO.Path]::PathSeparator + $env:PATH
$files = @("$ogg\src\framing.c", "$ogg\src\bitwise.c")
foreach ($name in @('mdct', 'smallft', 'block', 'envelope', 'window', 'lsp',
                    'lpc', 'analysis', 'synthesis', 'psy', 'info', 'floor1',
                    'floor0', 'res0', 'mapping0', 'registry', 'codebook',
                    'sharedbook', 'lookup', 'bitrate')) {
  $files += "$vorbis\lib\$name.c"
}
$files += @('fixups.c', 'ogg.c', 'oggseek.c', 'xiph_metadata.c')
$objects = @()
Push-Location $module
try {
  foreach ($file in $files) {
    $object = Join-Path $out (([IO.Path]::GetFileNameWithoutExtension($file)) + '.o')
    & $gcc -std=gnu11 -O2 -fstack-protector-strong -D__PLUGIN__ -DHAVE_LIBVORBIS `
      -DHAVE_ATTRIBUTE_PACKED -D_FILE_OFFSET_BITS=64 -D_REENTRANT -D_THREAD_SAFE `
      -D__MSVCRT_VERSION__=0x0700 -I "$sdk\include\vlc\plugins" -I "$vlc\include" `
      -I "$ogg\include" -I "$vorbis\include" -I "$vorbis\lib" -I . `
      "-ffile-prefix-map=$ogg=libogg" "-ffile-prefix-map=$vorbis=libvorbis" `
      -include prelude.h -c $file -o $object
    if ($LASTEXITCODE -ne 0) { throw "Ogg compilation failed: $file" }
    $objects += $object
  }
  & $gcc -shared -static-libgcc '-Wl,--no-insert-timestamp' '-Wl,--image-base,0x180000000' `
    @objects "$sdk\lib\libvlccore.lib" '-Wl,-Bstatic' -lssp '-Wl,-Bdynamic' -lm `
    -o "$out\libogg_plugin.dll"
  if ($LASTEXITCODE -ne 0) { throw 'Ogg demux linking failed.' }
} finally {
  Pop-Location
}
$actual = (Get-FileHash -LiteralPath "$out\libogg_plugin.dll" -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = '705b091683075d7aac22ef04c42bc3d5239a8b69f54c43df9cea8d87a2de9d09'
if ($actual -ne $expected) { throw "Build produced SHA-256 $actual; expected $expected." }
Write-Output "Built $out\libogg_plugin.dll (SHA-256 $actual)"
