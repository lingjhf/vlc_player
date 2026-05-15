# vlc_player

A Flutter plugin for video playback using VLC.

The plugin creates a native VLC-backed video view and exposes a Dart controller
for loading media, playback controls, seeking, volume, speed, and state updates.

## Supported platforms

- Android
- iOS
- macOS
- Windows
- Linux

The plugin forwards media URIs to the native VLC library. It does not keep a
Dart-side format allowlist or parse playlists in Dart.

Playback support depends on the platform VLC library and the codecs used by the
media source. Common VLC-supported sources include MP4, MOV, MKV, WebM, AVI,
FLV, MPEG-TS, HLS (`.m3u8`), DASH, RTSP, and RTP.

## Installation

Add the package to your app:

```yaml
dependencies:
  vlc_player: ^0.4.0
```

If you are using this repository directly:

```yaml
dependencies:
  vlc_player:
    path: ../vlc_player
```

Then run:

```sh
flutter pub get
```

Applications embedding this plugin must satisfy the binary distribution and
license requirements for libVLC, MobileVLCKit, VLCKit, and the VLC Windows
runtime.

## Platform setup

### Android

Network playback requires internet permission. The plugin manifest declares it:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

The plugin depends on `MobileVLCKit`.

If your app plays non-HTTPS URLs, configure App Transport Security in the app's
`Info.plist`. HTTPS URLs do not need ATS exceptions.

### macOS

The plugin depends on `VLCKit`.

For sandboxed apps that play network media, enable the network client
entitlement in the app:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

The macOS podspec patches the VLCKit runtime path during build. Use CocoaPods
`1.13.0` or newer so the script phase runs reliably.

After changing the macOS podspec or Pods state, run:

```sh
cd example/macos
pod install
```

### Windows

The Windows implementation downloads the VLC Windows runtime during
`flutter build windows` and bundles it into your app automatically.

```text
build/windows/x64/runner/Release/
  your_app.exe
  libvlc.dll
  libvlccore.dll
  plugins/
```

The build downloads VLC `3.0.21` for Windows x64 from VideoLAN and verifies the
archive SHA-256 before extraction. Windows builds require network access the
first time the runtime is downloaded.

Windows video is rendered through a Flutter texture backed by libVLC video
callbacks, so the Dart API is the same as the other platforms.
The native Windows implementation uses the vendored official `libvlcpp`
header-only bindings and links against the VLC SDK import library from the
downloaded runtime archive.

### Linux

The Linux implementation links against the system libVLC package through
pkg-config. Install VLC development files before building a Linux app:

```sh
sudo apt install libvlc-dev vlc
```

Linux video is rendered through a Flutter texture backed by libVLC video
callbacks, so the Dart API is the same as the other desktop platforms.
The native Linux implementation uses the vendored official `libvlcpp`
header-only bindings and links against the system `libvlc` package.

## Usage

### Play a video file

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
    source: Uri.parse('https://example.com/video.mp4'),
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

### Play an HLS stream

HLS playback is handled by the native VLC library. Pass the `.m3u8` playlist URL
as the source:

```dart
late final VlcPlayerController controller = VlcPlayerController(
  source: Uri.parse('https://example.com/live/playlist.m3u8'),
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
```

Playback commands require the controller to be attached to a `VlcPlayer`.
Calling commands such as `play()` before attachment throws a `StateError`.
Native platform failures throw `VlcPlayerException`, which exposes a structured
`VlcPlayerError` with `code`, `message`, and `details`.

`setSource()` and `setMedia()` can be called before attachment. The source is
replayed when the platform view is created.

## API

### VlcPlayer

`VlcPlayer` is the Flutter widget that creates the native platform video view.

```dart
VlcPlayer({
  Key? key,
  required VlcPlayerController controller,
  Color backgroundColor = Colors.black,
})
```

Parameters:

- `controller`: Controls the native VLC player attached to this widget.
- `backgroundColor`: Background color shown behind the native video view.

### VlcPlayerController

`VlcPlayerController` owns playback state and sends commands to the native VLC
player.

```dart
VlcPlayerController({
  Uri? source,
  VlcMediaSource? mediaSource,
  bool autoPlay = false,
  List<String> options = const <String>[],
  Map<String, String> httpHeaders = const <String, String>{},
})
```

Constructor parameters:

- `source`: Optional initial media URI.
- `mediaSource`: Optional initial `VlcMediaSource` for headers, media options,
  and a start position. Use either `source` or `mediaSource`.
- `autoPlay`: Starts playback automatically after `source` is set.
- `options`: VLC options passed to the native player when the platform view is
  created.
- `httpHeaders`: HTTP headers used when loading the initial `source`.

Methods:

- `setSource(Uri source, {bool autoPlay = false, Map<String, String> httpHeaders = const <String, String>{}})`: Loads a new media URI.
- `setMedia(VlcMediaSource source, {bool autoPlay = false})`: Loads a media URI
  with HTTP headers, VLC media options, and an optional start position.
- `play()`: Starts or resumes playback.
- `pause()`: Pauses playback.
- `stop()`: Stops playback.
- `seekTo(Duration position)`: Seeks to a non-negative playback position.
- `setVolume(int volume)`: Sets volume. Values are clamped to `0..200`.
- `setPlaybackSpeed(double speed)`: Sets playback speed. The value must be
  finite and greater than zero.
- `getAudioTracks()`: Returns available audio tracks.
- `setAudioTrack(int id)`: Selects an audio track by VLC track id.
- `getSubtitleTracks()`: Returns available embedded subtitle tracks.
- `setSubtitleTrack(int id)`: Selects an embedded subtitle track by VLC track
  id.
- `disableSubtitle()`: Disables subtitle rendering.
- `addSubtitle(Uri uri)`: Adds an external subtitle file or URL and selects it.
- `getMediaInfo()`: Returns basic metadata and discovered media tracks.
- `dispose()`: Releases the native player attached to this controller.

Track methods return `VlcTrackDescription`. `getMediaInfo()` returns
`VlcMediaInfo`, including title, artist, album, duration, and basic video,
audio, and subtitle track details when VLC exposes them.

### VlcMediaSource

`VlcMediaSource` describes one media item before it is passed to VLC.

```dart
final source = VlcMediaSource(
  uri: Uri.parse('https://example.com/video.mp4'),
  httpHeaders: const <String, String>{
    'Authorization': 'Bearer token',
  },
  mediaOptions: const <String>[
    ':network-caching=1200',
  ],
  startPosition: const Duration(seconds: 30),
);

await controller.setMedia(source, autoPlay: true);
```

`uri` must be non-empty and `startPosition` must be non-negative.

### VlcPlayerValue

`VlcPlayerValue` is emitted through `VlcPlayerController.value`.

Fields:

- `state`: Current `VlcPlaybackState`.
- `position`: Current playback position.
- `duration`: Media duration.
- `volume`: Current volume.
- `playbackSpeed`: Current playback speed.
- `isReady`: Whether the native player has reached a playable terminal or
  active playback state.
- `isSeekable`: Whether VLC reports the current media as seekable.
- `isLive`: Whether the current media looks like a non-seekable stream without a
  fixed duration.
- `videoSize`: Current decoded video size when VLC exposes it.
- `bufferingProgress`: Normalized buffering progress from `0.0` to `1.0` when
  the platform exposes it; otherwise `null`.
- `error`: Structured native playback error, when available.
- `errorDescription`: Native playback error text, when available.

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

### Listening for state changes

`VlcPlayerController` extends `ValueNotifier<VlcPlayerValue>`, so it can be used
with `ValueListenableBuilder`.

```dart
ValueListenableBuilder<VlcPlayerValue>(
  valueListenable: controller,
  builder: (context, value, child) {
    return Text('${value.state} ${value.position}');
  },
)
```

## Example app

The `example` app contains:

- A video file playback page.
- An HLS stream playback page.
- A full player page with play/pause, seek, time display, and orientation
  controls.

Run it on macOS:

```sh
cd example
flutter run -d macos
```

## Troubleshooting

### `player_not_found`

This usually means a command was sent after the native platform view was
disposed or before the controller attached to the current view. Keep one
`VlcPlayerController` per player widget and call `dispose()` from the owning
widget's `dispose()` method.

### Network playback fails

Check:

- The media URL is reachable from the device.
- Android has internet permission.
- macOS sandboxed apps have the network client entitlement.
- iOS ATS allows the URL if it is not HTTPS.
- Required HTTP headers are passed through `httpHeaders`.
- Linux has `libvlc-dev` and `vlc` installed.

### macOS `Library not loaded: VLCKit`

Run `pod install` in the macOS app directory and rebuild:

```sh
cd example/macos
pod install
cd ..
flutter build macos
```

Also make sure CocoaPods is `1.13.0` or newer.
