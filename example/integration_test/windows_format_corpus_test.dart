import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

// These files are deliberately external: large test corpora must not be copied
// into the application bundle or the user's system drive.
const _manifest = String.fromEnvironment('VLC_PLAYER_CORPUS_MANIFEST');
const _audioHost = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _manifest.isEmpty || _audioHost.isEmpty) {
    throw StateError(
      'Windows, VLC_PLAYER_CORPUS_MANIFEST and '
      'VLC_PLAYER_AV_HOST are required for output verification.',
    );
  }
  final cases = (jsonDecode(File(_manifest).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (cases.isEmpty) throw StateError('Corpus manifest is empty.');

  for (final item in cases) {
    final name = item['name'] as String;
    testWidgets('actual output: $name', (tester) async {
      final kind = item['kind'] as String;
      expect([
        'video',
        'audio',
        'av',
        'stereo',
        'downmix_51',
        'downmix_71',
      ], contains(kind));
      final source = item['uri'] as String?;
      final VlcMediaSource media;
      if (source != null) {
        media = VlcMediaSource.location(location: source);
      } else {
        final file = File(item['path'] as String);
        expect(await file.exists(), isTrue, reason: file.path);
        media = VlcMediaSource(uri: file.uri);
      }
      final controller = VlcPlayerController(
        options: (item['options'] as List?)?.cast<String>() ?? const <String>[],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
        description: '$name attachment',
        attempts: nativePlayerAttachmentAttempts,
      );
      await controller.setVolume(75);
      await controller.setMedia(media, autoPlay: true);
      await pumpUntil(
        tester,
        () =>
            controller.value.state == VlcPlaybackState.playing ||
            controller.value.hasError,
        description: '$name playback',
        attempts: 80,
      );
      expect(
        controller.value.hasError,
        isFalse,
        reason: controller.value.errorDescription,
      );
      if (kind == 'video' || kind == 'av') {
        final color = item['color'] as String;
        expect(['red', 'blue'], contains(color));
        await _expectRenderedPicture(tester, name, color);
        await _expectPicture(tester, controller, name, color);
        final width = item['width'] as int?;
        final height = item['height'] as int?;
        if (width != null && height != null) {
          await pumpUntil(
            tester,
            () =>
                controller.value.videoSize ==
                Size(width.toDouble(), height.toDouble()),
            description: '$name visible video size ${width}x$height',
            attempts: 40,
          );
        }
        final pixelAspect = item['pixel_aspect_ratio'] as num?;
        if (pixelAspect != null) {
          await pumpUntil(
            tester,
            () =>
                (controller.value.videoPixelAspectRatio - pixelAspect).abs() <
                .001,
            description: '$name pixel aspect ratio',
            attempts: 40,
          );
          await tester.pump();
          final rect = tester.getRect(find.byType(Texture));
          expect(rect.width / rect.height, closeTo(16 / 9, .01));
        }
      }
      if (kind == 'audio' || kind == 'av') {
        await _expectTone(name, item['frequency'] as int);
      }
      if (kind == 'stereo') {
        await _expectStereo(
          name,
          item['left_hz'] as int,
          item['right_hz'] as int,
        );
      }
      if (kind == 'downmix_51' || kind == 'downmix_71') {
        await _expectDownmix(name, kind);
      }
      final disconnect = item['disconnect'] as Map<String, dynamic>?;
      if (disconnect != null) {
        await File(disconnect['trigger'] as String).writeAsString('disconnect');
        final ack = File(disconnect['ack'] as String);
        await pumpUntil(
          tester,
          ack.existsSync,
          description: '$name publisher shutdown',
          attempts: 80,
        );
        await tester.pump(const Duration(seconds: 2));
        await controller.stop().timeout(const Duration(seconds: 10));
        final recovery = File(disconnect['recovery_path'] as String);
        expect(await recovery.exists(), isTrue, reason: recovery.path);
        await controller.setMedia(
          VlcMediaSource(uri: recovery.uri),
          autoPlay: true,
        );
        await pumpUntil(
          tester,
          () => controller.value.state == VlcPlaybackState.playing,
          description: '$name recovery playback',
          attempts: 80,
        );
        await _expectRenderedPicture(tester, '${name}_recovery', 'blue');
        await _expectPicture(tester, controller, '${name}_recovery', 'blue');
        await _expectTone('${name}_recovery', 880);
        // ignore: avoid_print
        print('DISCONNECT_RECOVERY_PASS $name');
      }
      await controller.stop().timeout(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // ignore: avoid_print
      print('CORPUS_PASS $name $kind');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

Future<void> _expectRenderedPicture(
  WidgetTester tester,
  String name,
  String color,
) async {
  final client = HttpClient();
  Object? lastError;
  try {
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
      try {
        final request = await client.getUrl(
          Uri.parse(
            '$_audioHost/picture',
          ).replace(queryParameters: {'color': color, 'label': name}),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200 &&
            (jsonDecode(body) as Map<String, dynamic>)['passed'] == true) {
          return;
        }
        lastError = body;
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  fail('$name did not display the expected $color picture: $lastError');
}

Future<void> _expectPicture(
  WidgetTester tester,
  VlcPlayerController controller,
  String name,
  String color,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      controller.value.hasError,
      isFalse,
      reason: controller.value.errorDescription,
    );
    try {
      final png = await controller.takeSnapshot(width: 176, height: 144);
      final codec = await ui.instantiateImageCodec(png);
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var matches = 0;
          var count = 0;
          for (var y = image.height ~/ 4; y < image.height * 3 ~/ 4; y += 3) {
            for (var x = image.width ~/ 4; x < image.width * 3 ~/ 4; x += 3) {
              final i = (y * image.width + x) * 4;
              final dominant = color == 'red' ? 0 : 2;
              final other = color == 'red' ? 2 : 0;
              if (pixels[i + dominant] > 150 &&
                  pixels[i + 1] < 90 &&
                  pixels[i + other] < 90) {
                matches++;
              }
              count++;
            }
          }
          if (count > 0 && matches / count > 0.85) return;
          lastError = '$color pixels $matches/$count';
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
  fail('$name did not produce the expected $color picture: $lastError');
}

Future<void> _expectTone(String name, int frequency) async {
  final uri = Uri.parse('$_audioHost/capture').replace(
    queryParameters: {
      'platform': 'windows',
      'label': name,
      'frequency': '$frequency',
    },
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: body);
    expect(
      (jsonDecode(body) as Map<String, dynamic>)['passed'],
      isTrue,
      reason: body,
    );
    // ignore: avoid_print
    print('CORPUS_AUDIO $name $body');
  } finally {
    client.close(force: true);
  }
}

Future<void> _expectStereo(String name, int left, int right) async {
  final uri = Uri.parse('$_audioHost/capture').replace(
    queryParameters: {
      'platform': 'windows',
      'label': name,
      'mode': 'stereo',
      'left': '$left',
      'right': '$right',
    },
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: body);
    expect(
      (jsonDecode(body) as Map<String, dynamic>)['passed'],
      isTrue,
      reason: body,
    );
    // ignore: avoid_print
    print('CORPUS_STEREO $name $body');
  } finally {
    client.close(force: true);
  }
}

Future<void> _expectDownmix(String name, String mode) async {
  final uri = Uri.parse('$_audioHost/capture').replace(
    queryParameters: {'platform': 'windows', 'label': name, 'mode': mode},
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: body);
    expect(
      (jsonDecode(body) as Map<String, dynamic>)['passed'],
      isTrue,
      reason: body,
    );
    // ignore: avoid_print
    print('CORPUS_DOWNMIX $name $body');
  } finally {
    client.close(force: true);
  }
}
