import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

const String _assetRoot = 'assets/format_fixtures';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('format compatibility', () {
    for (final format in _smokeFormats) {
      testWidgets('loads ${format.name}', (WidgetTester tester) async {
        await _runFormatCase(tester, format);
      });
    }

    for (final format in _videoContainerFormats) {
      testWidgets('loads ${format.name}', (WidgetTester tester) async {
        await _runFormatCase(tester, format);
      });
    }

    for (final format in _audioFormats) {
      testWidgets('loads ${format.name}', (WidgetTester tester) async {
        await _runFormatCase(tester, format);
      });
    }

    testWidgets('adds an external SRT subtitle', (WidgetTester tester) async {
      await _runFormatCase(
        tester,
        const _FormatCase(
          name: 'MP4 with SRT subtitle',
          assetPath: '$_assetRoot/video.mp4',
          expectsVideo: true,
          subtitleAssetPath: '$_assetRoot/captions.srt',
        ),
      );
    });
  });
}

const List<_FormatCase> _smokeFormats = <_FormatCase>[
  _FormatCase(
    name: 'MP4',
    assetPath: '$_assetRoot/video.mp4',
    expectsVideo: true,
  ),
  _FormatCase(
    name: 'HLS M3U8',
    hlsPlaylistAssetPath: '$_assetRoot/hls/playlist.m3u8',
    hlsSegmentAssetPath: '$_assetRoot/hls/segment.ts',
    expectsVideo: true,
  ),
];

const List<_FormatCase> _videoContainerFormats = <_FormatCase>[
  _FormatCase(
    name: 'MOV',
    assetPath: '$_assetRoot/video.mov',
    expectsVideo: true,
  ),
  _FormatCase(
    name: 'MKV',
    assetPath: '$_assetRoot/video.mkv',
    expectsVideo: true,
  ),
  _FormatCase(
    name: 'WebM',
    assetPath: '$_assetRoot/video.webm',
    expectsVideo: true,
  ),
  _FormatCase(
    name: 'MPEG-TS',
    assetPath: '$_assetRoot/video.ts',
    expectsVideo: true,
  ),
];

const List<_FormatCase> _audioFormats = <_FormatCase>[
  _FormatCase(
    name: 'MP3',
    assetPath: '$_assetRoot/audio.mp3',
    expectsAudio: true,
  ),
  _FormatCase(
    name: 'AAC M4A',
    assetPath: '$_assetRoot/audio.m4a',
    expectsAudio: true,
  ),
  _FormatCase(
    name: 'FLAC',
    assetPath: '$_assetRoot/audio.flac',
    expectsAudio: true,
  ),
  _FormatCase(
    name: 'Ogg Vorbis',
    assetPath: '$_assetRoot/audio.ogg',
    expectsAudio: true,
  ),
  _FormatCase(
    name: 'Opus',
    assetPath: '$_assetRoot/audio.opus',
    expectsAudio: true,
  ),
];

class _FormatCase {
  const _FormatCase({
    required this.name,
    this.assetPath,
    this.hlsPlaylistAssetPath,
    this.hlsSegmentAssetPath,
    this.expectsVideo = false,
    this.expectsAudio = false,
    this.subtitleAssetPath,
  }) : assert(
         assetPath != null ||
             (hlsPlaylistAssetPath != null && hlsSegmentAssetPath != null),
       );

  final String name;
  final String? assetPath;
  final String? hlsPlaylistAssetPath;
  final String? hlsSegmentAssetPath;
  final bool expectsVideo;
  final bool expectsAudio;
  final String? subtitleAssetPath;
}

Future<void> _runFormatCase(WidgetTester tester, _FormatCase format) async {
  final controller = VlcPlayerController(options: _playerOptions(format));
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 135,
            child: VlcPlayer(controller: controller),
          ),
        ),
      ),
    ),
  );

  await _pumpUntil(tester, () => controller.isAttached);
  expect(controller.isAttached, isTrue);

  final sourceUri = await _materializeSource(format);
  await controller.setSource(sourceUri, autoPlay: true);

  final subtitleAssetPath = format.subtitleAssetPath;
  if (subtitleAssetPath != null) {
    await controller.addSubtitle(await _materializeAsset(subtitleAssetPath));
  }

  final value = await _waitForUsablePlayback(tester, controller, format.name);
  final info = await controller.getMediaInfo();

  expect(value.hasError, isFalse);
  if (format.expectsVideo) {
    expect(
      value.videoSize != null || info.videoTracks.isNotEmpty,
      isTrue,
      reason: '${format.name} should expose video metadata.',
    );
  }
  if (format.expectsAudio) {
    expect(
      info.audioTracks.isNotEmpty ||
          info.duration > Duration.zero ||
          value.duration > Duration.zero,
      isTrue,
      reason: '${format.name} should expose audio metadata or duration.',
    );
  }

  await controller.stop();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<Uri> _materializeSource(_FormatCase format) async {
  final assetPath = format.assetPath;
  if (assetPath != null) {
    return _materializeAsset(assetPath);
  }

  final directory = await Directory.systemTemp.createTemp(
    'vlc_player_hls_fixture_',
  );
  final segment = File('${directory.path}${Platform.pathSeparator}segment.ts');
  final playlist = File(
    '${directory.path}${Platform.pathSeparator}playlist.m3u8',
  );
  await _writeAsset(format.hlsSegmentAssetPath!, segment);
  await _writeAsset(format.hlsPlaylistAssetPath!, playlist);
  return playlist.uri;
}

Future<Uri> _materializeAsset(String assetPath) async {
  final directory = await Directory.systemTemp.createTemp(
    'vlc_player_format_fixture_',
  );
  final file = File(
    '${directory.path}${Platform.pathSeparator}${assetPath.split('/').last}',
  );
  await _writeAsset(assetPath, file);
  return file.uri;
}

Future<void> _writeAsset(String assetPath, File file) async {
  final data = await rootBundle.load(assetPath);
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<VlcPlayerValue> _waitForUsablePlayback(
  WidgetTester tester,
  VlcPlayerController controller,
  String name,
) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 250));
    final value = controller.value;
    if (value.hasError) {
      fail('$name entered error state: ${value.error}');
    }
    if (_usableStates.contains(value.state) || value.isReady) {
      return value;
    }
  }
  fail('$name did not become playable. Last value: ${controller.value.state}');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 40 && !condition(); attempt += 1) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

List<String> _playerOptions(_FormatCase format) {
  if (Platform.isLinux || format.expectsAudio) {
    return const <String>['--aout=dummy'];
  }
  return const <String>['--no-audio'];
}

const Set<VlcPlaybackState> _usableStates = <VlcPlaybackState>{
  VlcPlaybackState.playing,
  VlcPlaybackState.paused,
  VlcPlaybackState.stopped,
  VlcPlaybackState.ended,
};
