import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _sample = String.fromEnvironment('VLC_PLAYER_OGM_SAMPLE');
const _output = String.fromEnvironment('VLC_PLAYER_OGM_OUTPUT');
const _preselect = bool.fromEnvironment('VLC_PLAYER_OGM_PRESELECT');
const _zeroCaching = bool.fromEnvironment('VLC_PLAYER_OGM_ZERO_CACHING');
const _expectCue = bool.fromEnvironment(
  'VLC_PLAYER_OGM_EXPECT_CUE',
  defaultValue: true,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _sample.isEmpty || _output.isEmpty) {
    throw StateError(
      'Windows, an OGM sample and output directory are required.',
    );
  }

  for (final trackIndex in _preselect ? [1] : [0, 1]) {
    testWidgets('capture OGM subtitle track $trackIndex', (tester) async {
      final controller = VlcPlayerController(
        options: [
          '--no-audio',
          if (_preselect) '--sub-track-id=4',
          if (_zeroCaching) '--file-caching=0',
        ],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 480,
                child: VlcPlayer(controller: controller),
              ),
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
      final clock = Stopwatch()..start();
      await controller.setMedia(
        VlcMediaSource(uri: File(_sample).uri),
        autoPlay: true,
      );
      List<VlcTrackDescription> tracks = [];
      for (var attempt = 0; attempt < 40; attempt++) {
        tracks = (await controller.getSubtitleTracks())
            .where((t) => t.id >= 0)
            .toList();
        if (tracks.length >= 2) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tracks.length, greaterThanOrEqualTo(2));
      if (_preselect) {
        expect(tracks[trackIndex].id, 4);
      } else {
        await controller.setSubtitleTrack(tracks[trackIndex].id);
      }
      // ignore: avoid_print
      print(
        'OGM_SUBTITLE_SELECT $trackIndex ${tracks[trackIndex].id} '
        '${controller.value.position.inMilliseconds} wall_ms=${clock.elapsedMilliseconds}',
      );
      final visiblePixels = <int>[];
      for (final time in [3200, 8000]) {
        await pumpUntil(
          tester,
          () => controller.value.position >= Duration(milliseconds: time),
          description: 'subtitle cue at $time',
          attempts: 70,
        );
        final image = await controller.takeSnapshot(width: 640, height: 480);
        expect(image, isNotEmpty);
        final output = File('$_output/ogm-subtitle-$trackIndex-$time.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(image);
        final whitePixels = await _countWhiteSubtitlePixels(image);
        visiblePixels.add(whitePixels);
        // ignore: avoid_print
        print(
          'OGM_SUBTITLE_SNAPSHOT $trackIndex ${tracks[trackIndex].id} '
          '${controller.value.position.inMilliseconds} white_pixels=$whitePixels ${output.path}',
        );
      }
      if (_expectCue) {
        expect(
          visiblePixels.every((count) => count > 500),
          isTrue,
          reason:
              'Expected both subtitle cues; white pixel counts: $visiblePixels',
        );
      }
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

// This detector is specific to the selected OGM sample, its two white cues,
// and the 640x480 reference snapshots. It checks presence, not text accuracy.
Future<int> _countWhiteSubtitlePixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  try {
    if (image.width != 640 || image.height != 480) {
      throw StateError('Unexpected OGM snapshot size');
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('Could not decode OGM snapshot');
    var count = 0;
    for (var y = 395; y < 465; y++) {
      for (var x = 140; x < 500; x++) {
        final offset = (y * image.width + x) * 4;
        if (bytes.getUint8(offset) > 220 &&
            bytes.getUint8(offset + 1) > 220 &&
            bytes.getUint8(offset + 2) > 220) {
          count++;
        }
      }
    }
    return count;
  } finally {
    image.dispose();
    codec.dispose();
  }
}
