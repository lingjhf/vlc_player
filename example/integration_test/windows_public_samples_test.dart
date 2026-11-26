import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _manifest = String.fromEnvironment('VLC_PLAYER_CORPUS_MANIFEST');
const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _manifest.isEmpty || _host.isEmpty) {
    throw StateError(
      'Windows, VLC_PLAYER_CORPUS_MANIFEST and '
      'VLC_PLAYER_AV_HOST are required.',
    );
  }
  final cases = (jsonDecode(File(_manifest).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (cases.isEmpty) throw StateError('Corpus manifest is empty.');
  for (final item in cases) {
    final name = item['name'] as String;
    testWidgets('public reference: $name', (tester) async {
      final kind = item['kind'] as String;
      expect(['reference_video', 'reference_audio'], contains(kind));
      final file = File(item['path'] as String);
      expect(await file.exists(), isTrue, reason: file.path);
      final controller = VlcPlayerController(
        options: [
          if (kind == 'reference_video') '--no-audio',
          ...((item['options'] as List?)?.cast<String>() ?? const <String>[]),
        ],
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
      await controller.setMedia(
        VlcMediaSource(
          uri: file.uri,
          startPosition: Duration(milliseconds: item['start_ms'] as int? ?? 0),
        ),
        autoPlay: true,
      );
      await pumpUntil(
        tester,
        () =>
            controller.value.state == VlcPlaybackState.playing ||
            controller.value.state == VlcPlaybackState.ended ||
            controller.value.hasError,
        description: '$name playback',
        attempts: 80,
      );
      expect(
        controller.value.hasError,
        isFalse,
        reason: controller.value.errorDescription,
      );
      expect(
        controller.value.state,
        VlcPlaybackState.playing,
        reason: '$name ended before playback could be verified',
      );
      final audioTrackName = item['audio_track_name'] as String?;
      if (audioTrackName != null) {
        VlcTrackDescription? selected;
        List<VlcTrackDescription> tracks = [];
        for (var i = 0; i < 40; i++) {
          tracks = await controller.getAudioTracks();
          final matches = tracks.where(
            (track) =>
                track.id >= 0 &&
                track.name.toLowerCase().contains(audioTrackName.toLowerCase()),
          );
          if (matches.length == 1) {
            selected = matches.single;
            break;
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(selected, isNotNull, reason: '$name audio track not found');
        await controller.setAudioTrack(selected!.id);
        // ignore: avoid_print
        print('PUBLIC_AUDIO_TRACK $name ${selected.id} ${selected.name}');
      }
      final minimumPositionMs = item['minimum_position_ms'] as int?;
      if (minimumPositionMs != null) {
        await pumpUntil(
          tester,
          () => controller.value.position.inMilliseconds >= minimumPositionMs,
          description: '$name playback position',
          attempts: 40,
        );
      }
      if (kind == 'reference_video') {
        await pumpUntil(
          tester,
          () => controller.value.videoSize != null,
          description: '$name video dimensions',
          attempts: 40,
        );
        final captureDelayMs = item['capture_delay_ms'] as int? ?? 0;
        if (captureDelayMs > 0) {
          await tester.pump(Duration(milliseconds: captureDelayMs));
        }
        final referenceFrames = <int>{
          await _compareVideo(tester, controller, name),
        };
        if (item['verify_motion'] == true) {
          for (var i = 0; i < 2; i++) {
            await tester.pump(const Duration(seconds: 1));
            referenceFrames.add(await _compareVideo(tester, controller, name));
          }
          expect(
            referenceFrames.length,
            greaterThan(1),
            reason: '$name did not display changing reference frames',
          );
        }
      } else {
        final captureDelayMs = item['capture_delay_ms'] as int? ?? 0;
        if (captureDelayMs > 0) {
          await tester.pump(Duration(milliseconds: captureDelayMs));
        }
        await _compareAudio(name);
      }
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // Record a pass only after stop has completed; a decoder can render a
      // frame correctly and still crash when playback is stopped.
      // ignore: avoid_print
      print('PUBLIC_PASS $name ${item['codec']}');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

Future<int> _compareVideo(
  WidgetTester tester,
  VlcPlayerController controller,
  String name,
) async {
  final client = HttpClient();
  Object? lastError;
  try {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 250));
      try {
        final png = await controller.takeSnapshot(width: 96, height: 54);
        final dimensions = controller.value.videoSize!;
        final uri = Uri.parse('$_host/reference-picture').replace(
          queryParameters: {
            'label': name,
            'width': '${dimensions.width.round()}',
            'height': '${dimensions.height.round()}',
          },
        );
        final request = await client.postUrl(uri);
        request.contentLength = png.length;
        request.add(png);
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200 &&
            (jsonDecode(body) as Map<String, dynamic>)['passed'] == true) {
          // ignore: avoid_print
          print('PUBLIC_PICTURE $name $body');
          return (jsonDecode(body) as Map<String, dynamic>)['reference_frame']
              as int;
        }
        lastError = body;
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  fail('$name did not match a decoded reference frame: $lastError');
}

Future<void> _compareAudio(String name) async {
  final uri = Uri.parse('$_host/capture').replace(
    queryParameters: {
      'platform': 'windows',
      'label': name,
      'mode': 'reference',
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
    print('PUBLIC_AUDIO $name $body');
  } finally {
    client.close(force: true);
  }
}
