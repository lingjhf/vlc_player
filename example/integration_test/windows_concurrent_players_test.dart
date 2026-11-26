import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');
const _media = String.fromEnvironment('VLC_PLAYER_SESSION_MEDIA');
const _directSound = bool.fromEnvironment('VLC_PLAYER_TEST_DIRECTSOUND');
const _blueStart = int.fromEnvironment(
  'VLC_PLAYER_BLUE_START_SECONDS',
  defaultValue: 17,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _host.isEmpty || _media.isEmpty) {
    throw StateError(
      'Windows, VLC_PLAYER_AV_HOST and VLC_PLAYER_SESSION_MEDIA are required.',
    );
  }
  testWidgets('concurrent players keep picture and audio ownership', (
    tester,
  ) async {
    final options = <String>[if (_directSound) '--aout=directsound'];
    final red = VlcPlayerController(options: options);
    final blue = VlcPlayerController(options: options);
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final file = File(_media);
    expect(await file.exists(), isTrue, reason: file.path);
    final uri = file.uri;
    Widget view({required bool includeRed}) => MaterialApp(
      home: Row(
        children: [
          if (includeRed)
            SizedBox(
              key: const ValueKey('red'),
              width: 320,
              height: 180,
              child: VlcPlayer(controller: red),
            ),
          SizedBox(
            key: const ValueKey('blue'),
            width: 320,
            height: 180,
            child: VlcPlayer(controller: blue),
          ),
        ],
      ),
    );
    await tester.pumpWidget(view(includeRed: true));
    await pumpUntil(
      tester,
      () => red.isAttached && blue.isAttached,
      description: 'both players attached',
      attempts: nativePlayerAttachmentAttempts,
    );
    await red.setVolume(75);
    await blue.setVolume(0);
    await Future.wait([
      red.setMedia(VlcMediaSource(uri: uri), autoPlay: true),
      blue.setMedia(
        VlcMediaSource(
          uri: uri,
          startPosition: Duration(seconds: _blueStart),
        ),
        autoPlay: true,
      ),
    ]);
    await pumpUntil(
      tester,
      () =>
          red.value.state == VlcPlaybackState.playing &&
          blue.value.state == VlcPlaybackState.playing,
      description: 'both players playing',
      attempts: 80,
    );
    await red.setVolume(75);
    await blue.setVolume(0);
    await _expectColor(tester, red, blue: false);
    await _expectColor(tester, blue, blue: true);
    await _expectTone(tester, 'concurrent_red', 440);
    await blue.setVolume(25);
    await _expectTone(tester, 'concurrent_red_louder', 440);
    await red.setVolume(25);
    await blue.setVolume(75);
    await _expectTone(tester, 'concurrent_blue_louder', 880);
    await red.setVolume(0);
    await blue.setVolume(75);
    await _expectTone(tester, 'concurrent_blue', 880);
    await tester.pumpWidget(view(includeRed: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(red.isAttached, isFalse);
    expect(blue.isAttached, isTrue);
    await _expectColor(tester, blue, blue: true);
    await _expectTone(tester, 'concurrent_after_detach', 880);
    await blue.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 6)));
}

Future<void> _expectColor(
  WidgetTester tester,
  VlcPlayerController controller, {
  required bool blue,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
    try {
      final bytes = await controller.takeSnapshot(width: 160, height: 90);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final image = frame.image;
          final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final pixels = rgba.buffer.asUint8List();
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
              final i = (y * image.width + x) * 4;
              if (pixels[i + (blue ? 2 : 0)] > 150 &&
                  pixels[i + 1] < 80 &&
                  pixels[i + (blue ? 0 : 2)] < 80) {
                matches++;
              }
              samples++;
            }
          }
          if (samples > 0 && matches / samples > .85) return;
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (error) {
      lastError = error;
    }
  }
  fail('Expected ${blue ? "blue" : "red"} picture; last error: $lastError');
}

Future<void> _expectTone(
  WidgetTester tester,
  String label,
  int frequency,
) async {
  await tester.pump(const Duration(milliseconds: 800));
  final client = HttpClient();
  try {
    final uri = Uri.parse('$_host/capture').replace(
      queryParameters: {
        'platform': 'windows',
        'label': label,
        'frequency': '$frequency',
        'reject_frequency': '${frequency == 440 ? 880 : 440}',
      },
    );
    final response = await (await client.getUrl(uri)).close();
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: body);
    expect(
      (jsonDecode(body) as Map<String, dynamic>)['passed'],
      isTrue,
      reason: body,
    );
  } finally {
    client.close(force: true);
  }
}
