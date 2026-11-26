import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _media = String.fromEnvironment('VLC_PLAYER_PERFORMANCE_MEDIA');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _media.isEmpty) {
    throw StateError('Windows and VLC_PLAYER_PERFORMANCE_MEDIA are required.');
  }
  for (final direct in [true, false]) {
    testWidgets('1080p playback: direct rendering $direct', (tester) async {
      final file = File(_media);
      expect(await file.exists(), isTrue, reason: file.path);
      final controller = VlcPlayerController(
        options: ['--no-audio', if (direct) '--avcodec-dr'],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 960,
              height: 540,
              child: VlcPlayer(controller: controller),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => controller.isAttached,
        description: 'player attachment',
        attempts: nativePlayerAttachmentAttempts,
      );
      await controller.setMedia(VlcMediaSource(uri: file.uri), autoPlay: true);
      await pumpUntil(
        tester,
        () => controller.value.state == VlcPlaybackState.playing,
        description: 'playback',
        attempts: 80,
      );
      await tester.pump(const Duration(seconds: 1));
      final before = await controller.getMediaStats();
      final start = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final after = await controller.getMediaStats();
      final displayed = after.displayedPictures - before.displayedPictures;
      final lost = after.lostPictures - before.lostPictures;
      final decoded = after.decodedVideo - before.decodedVideo;
      expect(decoded, greaterThan(0));
      expect(displayed, greaterThan(0));
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // Diagnostic results depend on machine load and are not a benchmark.
      // ignore: avoid_print
      print(
        'PERFORMANCE direct=$direct elapsed_ms=${start.elapsedMilliseconds} '
        'decoded=$decoded displayed=$displayed lost=$lost',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
