# vlc_player

A Flutter plugin for video playback using VLC.

`vlc_player` creates a native VLC-backed video view and exposes a Dart
controller for loading media, controlling playback, selecting tracks, handling
subtitles, reading playback state and media statistics, and capturing
snapshots.

## Supported platforms

- Android
- iOS
- macOS
- Windows
- Linux

The plugin forwards media URIs to the native VLC library. Supported media
formats, codecs, playlists, and stream protocols depend on the VLC runtime used
on the target platform. Common VLC-supported sources include MP4, MOV, MKV,
WebM, AVI, FLV, MPEG-TS, HLS (`.m3u8`), DASH, RTSP, and RTP.

## Installation

Add the package to your app:

```yaml
dependencies:
  vlc_player: ^2.1.3
```

Then run:

```sh
flutter pub get
```

Apps that embed this plugin must satisfy the binary distribution and license
requirements for libVLC, MobileVLCKit, VLCKit, and the VLC Windows runtime. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the third-party runtime
and source components that app distributors need to account for.

## Platform setup

### Android

Android apps must use `minSdk 29` or newer.

Network playback requires internet access. The plugin manifest declares:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

The iOS implementation requires iOS 13 or newer.

The iOS implementation depends on `MobileVLCKit`.

HTTPS media URLs work without extra transport configuration. If your app plays
non-HTTPS URLs, configure App Transport Security in the app's `Info.plist`.

### macOS

The macOS implementation requires macOS 10.15 or newer.

The macOS implementation depends on `VLCKit`.

For sandboxed apps that play network media, enable the network client
entitlement:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Use CocoaPods `1.13.0` or newer so the VLCKit runtime path script phase runs
reliably.

### Windows

The Windows implementation downloads the VLC Windows runtime during
`flutter build windows` and bundles it into your app automatically:

```text
build/windows/x64/runner/Release/
  your_app.exe
  libvlc.dll
  libvlccore.dll
  plugins/
```

The first Windows build requires network access to download verified VLC and
libopenmpt archives. It uses the VLC 3.0.21 runtime and the Opus, Speex,
and libavcodec modules from VLC 3.0.24 to fix multichannel Opus and AVI/Speex
header parsing and support interlaced VP5 decoding. These mixed-version modules
pass the tested playback and lifecycle cases, but matching exported symbols do
not guarantee compatibility for every input. The bundled Schroedinger
decoder is excluded and libavcodec's
direct rendering is disabled by default to avoid Dirac/VC-2 buffer corruption
in VLC 3.0.x. This adds a frame copy for affected software decoding paths and
may increase CPU or memory use; the Schroedinger Dirac encoder is also not
bundled. Explicitly overriding this default with `--avcodec-dr` can reintroduce
the crash. A media-free VLC instance and the Windows D3D11 library remain
loaded for the process lifetime to avoid crashes during repeated module
unloading; each player still has its own VLC instance and options.

The bundled Windows MMDevice audio output assigns separate Windows audio
sessions to simultaneous players so their volume and mute controls remain
independent. Session slots are reused after players close; Windows may retain
settings for a slot that a later player inherits. The modified module, license
notices, and reproducible build instructions are in
[`third_party/vlc_mmdevice`](third_party/vlc_mmdevice/README.md).

The Windows DVB subtitle decoder uses the standard default palette when a
referenced palette is unavailable. Subtitle content can remain visible, but
default colors cannot reproduce a missing custom palette. The modified module
and build instructions are in [`third_party/vlc_dvbsub`](third_party/vlc_dvbsub/README.md).

On Windows, advanced-profile VC-1 elementary streams with a `.vc1` suffix and
sequence header are automatically routed to VLC's VC-1 demuxer. The probe and
its limitations are documented in [`third_party/vlc_vc1`](third_party/vlc_vc1/README.md).
The Windows PVA demuxer also reports relative playback time; its clock and seek
limitations are documented in [`third_party/vlc_pva`](third_party/vlc_pva/README.md).
`tool/generate_windows_pva_wrap_fixture.py` can produce a timestamp-rollover
fixture from a suitable PVA sample without re-encoding its audio or video.

For tracker music on Windows, libopenmpt provides newer module decoding, while
VLC's original MOD module remains available as a fallback. Enabling the VLC
MOD reverb, bass enhancement, or surround options selects the original module;
files that it cannot decode, such as the tested older DSMI AMF versions, may
therefore remain unplayable with those effects enabled. Sources, license notices,
and build instructions are in [`third_party/vlc_openmpt`](third_party/vlc_openmpt/README.md).

On platforms using VLC 3.0's unmodified PVA demuxer, playback position can
remain at zero. A player dedicated to PVA can try
`options: ['--demux=avformat']` to use VLC's FFmpeg-based demuxer instead.
This option affects demuxer selection for that player, and support may vary
between files.

On some systems, VLC 3.0 may log video-converter errors before falling back
to software decoding for 10-bit AV1. Applications that need to avoid this
fallback can try `options: ['--codec=dav1d,any']`, which prefers the dav1d
software decoder while allowing VLC to select other decoders. This can forgo
hardware AV1 decoding and increase CPU use.

When an embedded Matroska subtitle track is enabled after a cue has already
started, VLC 3.0 can wait until the next cue before displaying subtitles. For
seekable media, an application can optionally call
`await controller.seekTo(controller.value.position)` after selecting the track
to refresh the current cue. This performs a seek and can briefly interrupt
playback; it is not available for non-seekable streams.
On Windows, the bundled Ogg demuxer corrects OGM text-subtitle timestamps.
The modified source and build details are in
[`third_party/vlc_ogg`](third_party/vlc_ogg/README.md). Selecting a track after
a cue has begun can still depend on VLC's buffering and seek behavior.

Windows also supports raw Shorten (`.shn`) streams containing 8- or 16-bit
WAVE audio, or mono/stereo AIFF audio. For AIFF-C, the `NONE` and `sowt`
encodings are supported. Seeking decodes from the beginning and can take
longer on large files. The module and its limitations are documented in
[`third_party/vlc_shorten`](third_party/vlc_shorten/README.md).

### Linux

The Linux implementation links against the system libVLC package through
pkg-config. Install VLC development files before building a Linux app:

```sh
sudo apt install libvlc-dev vlc
```

## Usage

### Create a player

```dart
import 'package:flutter/material.dart';
import 'package:vlc_player/vlc_player.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VlcPlayerController controller = VlcPlayerController(
    mediaSource: VlcMediaSource(
      uri: Uri.parse('https://example.com/video.mp4'),
    ),
    autoPlay: true,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: VlcPlayer(controller: controller),
    );
  }
}
```

`setMedia()` can be called before the controller is attached to a `VlcPlayer`.
Commands such as `play()`, `pause()`, and `seekTo()` require an attached player
and throw `StateError` if called too early or after disposal.

A controller can belong to one mounted `VlcPlayer` at a time. Unmount the old
widget before reusing its controller in another widget. Media and playlist
changes execute in invocation order; a failed change rolls back before the next
change starts. Await the returned futures to handle individual loading errors.

### Play an HLS stream

Pass the `.m3u8` playlist URL as the media source:

```dart
final controller = VlcPlayerController(
  mediaSource: VlcMediaSource(
    uri: Uri.parse('https://example.com/live/playlist.m3u8'),
  ),
  autoPlay: true,
);
```

VLC's UDP listener syntax includes an `@` that Dart's `Uri` normalizes away.
On Windows, use an exact location to preserve it:

```dart
await controller.setMedia(
  VlcMediaSource.location(location: 'udp://@127.0.0.1:12345'),
  autoPlay: true,
);
```

### Load media with headers and VLC options

Use `VlcMediaSource` when a URL needs request headers, per-item VLC media
options, or an initial seek position:

```dart
await controller.setMedia(
  VlcMediaSource(
    uri: Uri.parse('https://example.com/protected/video.mp4'),
    httpHeaders: const <String, String>{
      'Authorization': 'Bearer token',
    },
    mediaOptions: const <String>[
      ':network-caching=1200',
    ],
    startPosition: const Duration(seconds: 30),
  ),
  autoPlay: true,
);
```

### Control playback

```dart
await controller.play();
await controller.pause();
await controller.seekTo(const Duration(seconds: 30));
await controller.setVolume(100);
await controller.setPlaybackSpeed(1.25);
await controller.setAudioDelay(const Duration(milliseconds: -120));
await controller.setSubtitleDelay(const Duration(milliseconds: 250));
await controller.stop();
```

### Fit the video

Use `VlcPlayer.fit` to choose how the video is fitted inside the widget:

```dart
VlcPlayer(
  controller: controller,
  fit: VlcVideoFit.cover,
)
```

Available values are `contain`, `cover`, `fill`, and `none`.

### Capture a snapshot

```dart
final pngBytes = await controller.takeSnapshot(width: 320);
debugPrint('snapshot bytes=${pngBytes.length}');
```

When only `width` or `height` is provided, VLC preserves the source aspect ratio
where the platform backend supports it.

### Play a playlist

```dart
await controller.setPlaylist(
  <VlcMediaSource>[
    VlcMediaSource(uri: Uri.parse('https://example.com/episode-1.mp4')),
    VlcMediaSource(uri: Uri.parse('https://example.com/episode-2.mp4')),
  ],
  autoPlay: true,
  autoAdvance: true,
  loopMode: VlcPlaylistLoopMode.loopAll,
);

await controller.next();
await controller.previous();
await controller.jumpTo(0);
await controller.addToPlaylist(
  VlcMediaSource(uri: Uri.parse('https://example.com/bonus.mp4')),
);
await controller.shufflePlaylist(seed: 42);
```

Playlist state is available through `playlist`, `playlistIndex`,
`playlistLoopMode`, `currentMediaSource`, `hasNext`, and `hasPrevious`.

### Select tracks and subtitles

```dart
final audioTracks = await controller.getAudioTracks();
if (audioTracks.isNotEmpty) {
  await controller.setAudioTrack(audioTracks.first.id);
}

final subtitleTracks = await controller.getSubtitleTracks();
if (subtitleTracks.isNotEmpty) {
  await controller.setSubtitleTrack(subtitleTracks.first.id);
}

await controller.addSubtitle(Uri.file('/path/to/subtitles.srt'));
await controller.disableSubtitle();

final info = await controller.getMediaInfo();
debugPrint('duration=${info.duration}');

final stats = await controller.getMediaStats();
if (stats.isAvailable) {
  debugPrint('decoded video blocks=${stats.decodedVideo}');
}
```

Track selection methods use native VLC track ids returned by
`getAudioTracks()` and `getSubtitleTracks()`.

### Listen for state changes

`VlcPlayerController` extends `ValueNotifier<VlcPlayerValue>`.

```dart
ValueListenableBuilder<VlcPlayerValue>(
  valueListenable: controller,
  builder: (context, value, child) {
    return Text('${value.state} ${value.position}');
  },
)
```

Native platform failures throw `VlcPlayerException` and may also be exposed
through `VlcPlayerValue.error`.

```dart
try {
  await controller.play();
} on VlcPlayerException catch (error) {
  debugPrint('VLC command failed: ${error.code} ${error.message}');
}
```

## API

The supported application-facing API is exported from:

```dart
import 'package:vlc_player/vlc_player.dart';
```

Native view attachment, texture creation, method channels, and platform view
type details are implementation internals.

### VlcPlayer

`VlcPlayer` is the Flutter widget that hosts the native VLC video output.

```dart
const VlcPlayer({
  Key? key,
  required VlcPlayerController controller,
  Color backgroundColor = Colors.black,
  VlcVideoFit fit = VlcVideoFit.contain,
})
```

- `controller`: controller used to load media, control playback, and observe
  state.
- `backgroundColor`: color shown behind the native video output.
- `fit`: video fitting behavior inside the widget bounds.

### VlcPlayerController

`VlcPlayerController` owns playback state and sends commands to the native VLC
player.

```dart
VlcPlayerController({
  VlcMediaSource? mediaSource,
  bool autoPlay = false,
  List<String> options = const <String>[],
  Duration? eventThrottleInterval,
})
```

- `mediaSource`: optional initial media item.
- `autoPlay`: starts playback after the initial media source is loaded.
- `options`: VLC instance options applied when the native player is created.
- `eventThrottleInterval`: optional interval for coalescing progress-only
  native events.

Important properties:

- `value`: current `VlcPlayerValue`.
- `isAttached`: whether the controller is attached to a native player.
- `playlist`, `playlistIndex`, `playlistLoopMode`: current playlist state.
- `currentMediaSource`: active or pending media source.
- `hasNext`, `hasPrevious`: whether playlist navigation can move without
  wrapping.

Media and playlist methods:

- `setMedia(VlcMediaSource source, {bool autoPlay = false})`
- `setPlaylist(List<VlcMediaSource> sources, {int initialIndex = 0, bool autoPlay = false, bool autoAdvance = true, VlcPlaylistLoopMode loopMode = VlcPlaylistLoopMode.none})`
- `next({bool autoPlay = true})`
- `previous({bool autoPlay = true})`
- `jumpTo(int index, {bool autoPlay = true})`
- `addToPlaylist(VlcMediaSource source)`
- `insertIntoPlaylist(int index, VlcMediaSource source)`
- `removeFromPlaylistAt(int index, {bool autoPlay = true})`
- `clearPlaylist()`
- `shufflePlaylist({int? seed})`

Playback methods:

- `play()`
- `pause()`
- `stop()`
- `seekTo(Duration position)`
- `setVolume(int volume)`
- `setPlaybackSpeed(double speed)`
- `setAudioDelay(Duration delay)`
- `setSubtitleDelay(Duration delay)`
- `takeSnapshot({int? width, int? height})`

Track, subtitle, and media information methods:

- `getAudioTracks()`
- `setAudioTrack(int id)`
- `getSubtitleTracks()`
- `setSubtitleTrack(int id)`
- `disableSubtitle()`
- `addSubtitle(Uri uri)`
- `getMediaInfo()`
- `getMediaStats()`

`setVolume()` clamps values to VLC's `0..200` range. `seekTo()` requires a
non-negative position. `setPlaybackSpeed()` requires a finite value greater
than zero.

### VlcMediaSource

`VlcMediaSource` describes one media item before it is passed to VLC.

```dart
VlcMediaSource({
  required Uri uri,
  Map<String, String> httpHeaders = const <String, String>{},
  List<String> mediaOptions = const <String>[],
  Duration startPosition = Duration.zero,
})
```

- `uri`: non-empty media URI to load.
- `httpHeaders`: HTTP headers used when opening the media.
- `mediaOptions`: VLC media options applied only to this source.
- `startPosition`: non-negative initial playback position.

### VlcPlayerValue

`VlcPlayerValue` is the immutable playback snapshot emitted by the controller.

Fields:

- `state`
- `position`
- `duration`
- `volume`
- `playbackSpeed`
- `audioDelay`
- `subtitleDelay`
- `isReady`
- `isSeekable`
- `isLive`
- `videoSize`
- `videoPixelAspectRatio` (Windows and Linux; defaults to `1` when unavailable)
- `bufferingProgress`
- `error`
- `errorDescription`

Convenience getters:

- `isPlaying`
- `isBuffering`
- `hasError`

### VlcPlaybackState

Possible playback states:

- `idle`
- `opening`
- `buffering`
- `playing`
- `paused`
- `stopped`
- `ended`
- `error`

### VlcVideoFit

Possible video fitting values:

- `contain`
- `cover`
- `fill`
- `none`

### VlcPlaylistLoopMode

Possible playlist loop values:

- `none`
- `loopOne`
- `loopAll`

### Track, media information, and media statistics

`getAudioTracks()` and `getSubtitleTracks()` return
`VlcTrackDescription` objects:

- `id`: native VLC track id.
- `name`: track name reported by VLC.
- `language`: optional language code or label reported by VLC.

`getMediaInfo()` returns `VlcMediaInfo`:

- `title`, `artist`, `album`: metadata discovered by VLC when available.
- `duration`: media duration, or `Duration.zero` when unknown.
- `videoTracks`, `audioTracks`, `subtitleTracks`: lists of
  `VlcMediaTrackInfo`.

`VlcMediaTrackInfo` includes `type`, `codec`, `language`, `bitrate`, `width`,
`height`, `channels`, and `sampleRate`. These values are best-effort because
containers and streams do not always expose every field.

`getMediaStats()` returns `VlcMediaStats`:

- `isAvailable`: whether VLC reported statistics for the current media.
- `readBytes`, `inputBitrate`: current input module counters.
- `demuxReadBytes`, `demuxBitrate`, `demuxCorrupted`,
  `demuxDiscontinuity`: current demux counters.
- `decodedVideo`, `decodedAudio`: decoded block counters.
- `displayedPictures`, `lostPictures`: video output counters.
- `playedAudioBuffers`, `lostAudioBuffers`: audio output counters.
- `sentPackets`, `sentBytes`, `sendBitrate`: stream-output counters.

When no media is loaded or VLC cannot provide statistics, `isAvailable` is
`false` and the numeric values are zero.

### Errors

Native command failures are exposed as `VlcPlayerException`, which wraps a
structured `VlcPlayerError`.

`VlcPlayerError` exposes:

- `code`
- `message`
- `details`
- `description`

Common error codes are available in `VlcPlayerErrorCode`, including
`invalidArgs`, `playerNotFound`, `createFailed`, `setSourceFailed`,
`trackNotFound`, `addSubtitleFailed`, `playbackError`, `disposed`, and
`eventChannelError`.

## API stability

The `2.x` line follows Semantic Versioning. Backward-compatible additions use
minor versions, fixes use patch versions, and breaking API, platform, or
behavior changes use major versions.

Native view attachment, texture creation, method channels, platform view type
strings, and generated platform registration details are implementation
internals. Applications should import only `package:vlc_player/vlc_player.dart`
and use the public types documented above.

## Migrating from 1.x or 0.8.x

Version `2.0.0` requires Android `minSdk 29` or newer.

The Dart-facing API remains backward compatible, but Android apps that still
target a lower minimum SDK must raise it before upgrading.

## Migrating from 0.7.21 or earlier

For apps migrating from older releases that used `source`, `httpHeaders`, or
`setSource()`, use `VlcMediaSource` and `setMedia()` instead:

```dart
final controller = VlcPlayerController(
  mediaSource: VlcMediaSource(
    uri: Uri.parse('https://example.com/video.mp4'),
    httpHeaders: const <String, String>{
      'Authorization': 'Bearer token',
    },
  ),
  autoPlay: true,
);

await controller.setMedia(
  VlcMediaSource(uri: Uri.parse('https://example.com/next.mp4')),
  autoPlay: true,
);
```

## Troubleshooting

### `player_not_found`

This usually means a command was sent after the native player was disposed or
before the controller attached to the current `VlcPlayer`. Keep one
`VlcPlayerController` per player widget and call `dispose()` from the owning
widget's `dispose()` method.

### Network playback fails

Check that:

- The media URL is reachable from the device.
- Android has internet permission.
- macOS sandboxed apps have the network client entitlement.
- iOS allows the URL through App Transport Security if it is not HTTPS.
- Required HTTP headers are passed through `VlcMediaSource.httpHeaders`.
- Linux has `libvlc-dev` and `vlc` installed.

### macOS `Library not loaded: VLCKit`

Run `pod install` in the macOS app directory and rebuild:

```sh
cd macos
pod install
cd ..
flutter build macos
```

Also make sure CocoaPods is `1.13.0` or newer.

## Development checks

For session regression checks, run
`flutter drive -d <device> --driver=test_driver/integration_test.dart --target=integration_test/session_lifecycle_test.dart`
from `example/`. This verifies red/blue video frames, overlapping source changes,
and controller reuse. On Android emulators, use
`--driver=test_driver/android_lifecycle_test.dart` to provide system screenshots.
CI uses dummy audio output. To verify actual output audio,
start `tool/verify_session_output.py --help` from the repository root and follow
its setup instructions, then add
`--dart-define=VLC_PLAYER_AV_HOST=http://127.0.0.1:45939` to the drive command.
The host saves recordings and checks 440/880 Hz tones and paused silence without
using a microphone. Regenerate the fixture with
`python tool/generate_session_fixture.py --ffmpeg <ffmpeg-path>`.

For a wider Windows format check, the optional external corpus keeps large
samples and recordings outside the repository. Use a local FFmpeg/FFprobe build
and a Python environment containing `numpy`, `soundcard`, and `Pillow`. For
example, from the repository root in PowerShell:

```powershell
python tool/generate_windows_format_corpus.py --ffmpeg <ffmpeg.exe> --output-dir E:/vlc-player-format-validation/samples/synthetic
python tool/verify_session_output.py --ffmpeg <ffmpeg.exe> --output-dir E:/vlc-player-format-validation/results --capture-seconds 2
```

Leave the capture host running, then in another terminal run the following from
`example/` with the example application in the foreground:

```powershell
flutter drive --no-dds -d windows --dart-define=VLC_PLAYER_CORPUS_MANIFEST=E:/vlc-player-format-validation/samples/synthetic/manifest.json --dart-define=VLC_PLAYER_AV_HOST=http://127.0.0.1:45939 --driver=test_driver/integration_test.dart --target=integration_test/windows_format_corpus_test.dart
```

The synthetic matrix alternates red and blue frames and 440/880 Hz tones. It
checks the center of the foreground example window as well as VLC snapshots and
actual system loopback audio; it does not use a microphone. Each generated case
and any unavailable encoder are listed in the output directory. A passing
matrix only establishes the tested combinations, not all VLC capabilities.

`tool/download_windows_format_samples.py` can also download public FFmpeg
samples into a specified external directory and records their source URLs and
hashes. Run `tool/prepare_windows_sample_references.py` on that directory to
create independently decoded references. Restart the capture host with
`--reference-manifest <directory>/manifest.json`, and run the same drive command
with that manifest and `integration_test/windows_public_samples_test.dart` as
the target. Public reference videos compare VLC snapshots against decoded
frames and the foreground window, and reference audio compares recorded output
with decoded waveforms at the full 48 kHz capture rate to avoid frequency
aliasing. Audio comparisons require a normalized correlation of at least 0.8;
lower scores are inconclusive and need another sample or a more
specific check. Windows loopback captures reporting discontinuities fail even
if their waveform otherwise matches. Download or reference generation failures
remain in the corresponding JSON report. Run
`python -m unittest discover -s test -p test_reference_audio.py` to check the
waveform verifier, including its frequency-aliasing negative control. Run
`python -m unittest discover -s test -p test_windows_audio_capture.py` to check
that a discontinuous loopback recording cannot pass.

To check the Dirac/VC-2 playback regression, run
`python tool/generate_windows_vc2_fixture.py --ffmpeg <ffmpeg.exe> --output-dir <directory>`
and use its manifest with the public-reference drive test and capture host.
To check raw VC-1, `tool/extract_windows_vc1_fixture.py` requires PyAV and a
WMV/ASF source with a VC-1 video stream. It restores elementary-stream headers
without re-encoding, after which `tool/prepare_windows_sample_references.py`
can prepare the public-reference drive test.
To test MIDI, provide an external SF2 SoundFont to
`python tool/generate_windows_midi_fixture.py --soundfont <file.sf2> --output-dir <directory>`
and use its manifest with the synthetic corpus drive test. The font is passed
to VLC through the per-player options and is not bundled by the plugin.
For a ProTracker MOD check, run
`python tool/generate_windows_mod_fixture.py --ffmpeg <ffmpeg.exe> --output-dir <directory>`
with an FFmpeg build that includes libopenmpt, then use its manifest with the
public-reference drive test.
For tracker files with prominent high frequencies, the default Windows MOD
noise filter can change the reference waveform substantially. Generate a
matching reference with `tool/prepare_windows_tracker_reference.py` and use its
manifest with the public-reference drive test. This checks the playback and
filter path against FFmpeg's libopenmpt decoder; because both use libopenmpt,
it is not an independent check of tracker playback semantics. Pass
`--libxmp <libxmp.dll>` to generate an independently decoded reference instead.
To check patterned high-bit-depth and chroma profiles, generate samples with
`python tool/generate_windows_video_profiles.py --ffmpeg <ffmpeg.exe> --output-dir <directory>`,
then use `tool/prepare_windows_sample_references.py` and the public-reference
drive test described above.
`tool/generate_windows_stereo_fixtures.py` and
`tool/generate_windows_surround_fixtures.py` generate channel-identification
tones for the corpus drive test. A stereo loopback can verify channel routing
and surround-to-stereo downmixing, but cannot validate a physical surround setup;
the downmix check does not require the LFE channel to be present.
For an RTP disconnect check, `tool/serve_windows_rtp_fixture.py` publishes a
loopback RTP/MPEG-TS stream and stops it when the corpus test creates its
trigger file; use a fresh external control directory for each run.
For embedded subtitles, use `tool/generate_windows_embedded_subtitle_fixtures.py`
with an external DVD subtitle sample and run
`integration_test/windows_embedded_subtitle_test.dart` with the generated
manifest and the capture host. This checks selecting and disabling subtitle
tracks against visible pixels; subtitle timing and content require separate
reference checks.
The generator also accepts optional PGS and DVB sources. For default DVB
palette checks, `tool/generate_windows_dvb_palette_fixtures.py` requires PyAV
and a Matroska DVB subtitle source using composition and ancillary page IDs 1.
It produces 2-bit and 4-bit color bands, an 8-bit sample and a grid covering
all 256 8-bit entries, along with independent FFmpeg reference images. Start
the capture host with the generated `--reference-manifest` and run the
embedded-subtitle drive test with the same manifest. Each band or grid cell is
checked independently against its reference composite, including transparent
and partially transparent entries. The verifier's negative controls can be run
with `python -m unittest discover -s test -p test_dvb_palette_reference.py`.

For external subtitle rendering, generate fixtures with
`python tool/generate_windows_subtitle_fixtures.py --output-dir <directory>`,
then drive `integration_test/windows_subtitle_corpus_test.dart` with
`VLC_PLAYER_SUBTITLE_MANIFEST`, `VLC_PLAYER_SUBTITLE_VIDEO`, and
`VLC_PLAYER_AV_HOST` set using `--dart-define`. The video should show a red
picture for at least 12 seconds, such as `session_av.mp4`. The test compares
foreground-window pixels before and after adding each subtitle. The optional
`tool/serve_windows_format_corpus.py` serves external fixtures on localhost
with byte-range support for HTTP streaming tests.
