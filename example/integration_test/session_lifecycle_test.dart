import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

// Optional loopback host verifies actual output audio, rather than VLC metadata.
// On a USB Android device, use `adb reverse tcp:45939 tcp:45939` and pass
// --dart-define=VLC_PLAYER_AV_HOST=http://127.0.0.1:45939.
const _audioHost = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'session reuse and queued source changes preserve picture and sound',
    (tester) async {
      final controller = VlcPlayerController(
        options: _audioHost.isEmpty
            ? headlessPlayerOptions(requiresAudio: true)
            : const [],
      );
      addTearDown(controller.dispose);
      final uri = await materializeAsset(
        'assets/format_fixtures/session_av.mp4',
      );
      final red = VlcMediaSource(uri: uri);
      final blue = VlcMediaSource(
        uri: uri,
        startPosition: const Duration(seconds: 17),
      );

      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: SizedBox(
                  width: 640,
                  height: 360,
                  child: VlcPlayer(controller: controller),
                ),
              ),
            ),
          ),
        );
        await pumpUntil(
          tester,
          () => controller.isAttached,
          attempts: nativePlayerAttachmentAttempts,
          description: 'session attachment',
        );
      }

      await mount();
      await controller.setVolume(75);
      await controller.setMedia(red, autoPlay: true);
      await _expectPicture(tester, controller, blue: false);
      await _expectPlaying(tester, controller);
      await _captureAudio('initial-red', 440);

      await controller.pause();
      await tester.pump(const Duration(milliseconds: 800));
      await _captureAudio('paused', 0);

      // These deliberately overlap at the public API boundary.
      await Future.wait([
        controller.setPlaylist([red, blue], autoPlay: true),
        controller.next(),
        controller.setMedia(red, autoPlay: true),
        controller.setMedia(blue, autoPlay: true),
      ]);
      expect(controller.currentMediaSource, blue);
      expect(controller.playlist, isEmpty);
      expect(controller.playlistIndex, isNull);
      await _expectPicture(tester, controller, blue: true);
      await _expectPlaying(tester, controller);
      await _captureAudio('queued-blue', 880);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.isAttached, isFalse);
      await controller.setMedia(red, autoPlay: true);
      await mount();
      await _expectPicture(tester, controller, blue: false);
      await _expectPlaying(tester, controller);
      await _captureAudio('remounted-red', 440);
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.isAttached, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _expectPicture(
  WidgetTester tester,
  VlcPlayerController controller, {
  required bool blue,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      controller.value.hasError,
      isFalse,
      reason: controller.value.errorDescription,
    );
    try {
      final bytes = Platform.isAndroid
          ? await _androidScreenshot()
          : await controller.takeSnapshot(width: 160, height: 90);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final pixels = rgba!.buffer.asUint8List();
          var matches = 0;
          var samples = 0;
          for (
            var y = image.height * 3 ~/ 8;
            y < image.height * 5 ~/ 8;
            y += 3
          ) {
            for (
              var x = image.width * 3 ~/ 8;
              x < image.width * 5 ~/ 8;
              x += 3
            ) {
              final offset = (y * image.width + x) * 4;
              final dominant = pixels[offset + (blue ? 2 : 0)];
              final other = pixels[offset + (blue ? 0 : 2)];
              if (dominant > 150 && other < 80 && pixels[offset + 1] < 80) {
                matches++;
              }
              samples++;
            }
          }
          if (matches / samples > 0.85) {
            debugPrint(
              'PICTURE ${blue ? "blue" : "red"}: '
              '${controller.value.state}, ${controller.value.position}, '
              '${controller.value.videoSize}',
            );
            return;
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (error) {
      lastError = error;
    }
  }
  fail(
    'Expected ${blue ? "blue" : "red"} video pixels. '
    'State: ${controller.value.state}, position: ${controller.value.position}, '
    'video size: ${controller.value.videoSize}. Last screenshot error: $lastError',
  );
}

Future<void> _expectPlaying(
  WidgetTester tester,
  VlcPlayerController controller,
) async {
  await pumpUntil(
    tester,
    () => controller.value.isPlaying,
    description: 'playing state after buffering',
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(
    controller.value.isPlaying,
    isTrue,
    reason: 'Finishing buffering must not overwrite the playing state.',
  );
}

Future<Uint8List> _androidScreenshot() async {
  const lifecycleHost = String.fromEnvironment(
    'VLC_PLAYER_ANDROID_LIFECYCLE_HOST',
    defaultValue: '10.0.2.2',
  );
  const lifecyclePort = int.fromEnvironment(
    'VLC_PLAYER_ANDROID_LIFECYCLE_PORT',
    defaultValue: 45937,
  );
  final uri = Uri.parse(
    _audioHost.isEmpty
        ? 'http://$lifecycleHost:$lifecyclePort/android-lifecycle/screenshot'
        : '$_audioHost/screenshot',
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    if (response.statusCode != 200) {
      throw StateError(utf8.decode(bytes.takeBytes(), allowMalformed: true));
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}

Future<void> _captureAudio(String label, int frequency) async {
  if (_audioHost.isEmpty) return;
  final uri = Uri.parse('$_audioHost/capture').replace(
    queryParameters: {
      'platform': Platform.operatingSystem,
      'label': label,
      'frequency': '$frequency',
    },
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: body);
    final report = jsonDecode(body) as Map<String, dynamic>;
    expect(report['passed'], isTrue, reason: body);
    // ignore: avoid_print
    print('OUTPUT_AUDIO $label: $body');
  } finally {
    client.close(force: true);
  }
}
