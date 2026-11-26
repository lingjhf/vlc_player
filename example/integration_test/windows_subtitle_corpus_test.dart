import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _manifest = String.fromEnvironment('VLC_PLAYER_SUBTITLE_MANIFEST');
const _video = String.fromEnvironment('VLC_PLAYER_SUBTITLE_VIDEO');
const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows ||
      _manifest.isEmpty ||
      _video.isEmpty ||
      _host.isEmpty) {
    throw StateError(
      'Windows, a subtitle manifest, video file, and capture host are required.',
    );
  }
  final cases = (jsonDecode(File(_manifest).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (cases.isEmpty) throw StateError('Subtitle manifest is empty.');
  for (final item in cases) {
    final name = item['name'] as String;
    testWidgets('render subtitle: $name', (tester) async {
      final controller = VlcPlayerController(options: const ['--no-audio']);
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
      await controller.setMedia(
        VlcMediaSource(uri: File(_video).uri),
        autoPlay: true,
      );
      await pumpUntil(
        tester,
        () => controller.value.videoSize != null,
        description: '$name video dimensions',
        attempts: 80,
      );
      final baseline = await _waitForPicture(
        tester,
        controller,
        '${name}_before',
        (report) =>
            (report['red_fraction'] as num) > .9 &&
            (report['neutral_fraction'] as num) < .001,
      );
      await controller.addSubtitle(File(item['path'] as String).uri);
      final rendered = await _waitForPicture(
        tester,
        controller,
        '${name}_rendered',
        (report) =>
            (report['red_fraction'] as num) > .75 &&
            (report['neutral_pixels'] as num) > 50 &&
            (report['neutral_fraction'] as num) >
                (baseline['neutral_fraction'] as num) + .001,
      );
      // ignore: avoid_print
      print('SUBTITLE_PASS $name $rendered');
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

Future<Map<String, dynamic>> _waitForPicture(
  WidgetTester tester,
  VlcPlayerController controller,
  String label,
  bool Function(Map<String, dynamic>) accepts,
) async {
  final client = HttpClient();
  Object? lastError;
  try {
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 150));
      try {
        final size = controller.value.videoSize!;
        final uri = Uri.parse('$_host/subtitle-picture').replace(
          queryParameters: {
            'label': label,
            'width': '${size.width.round()}',
            'height': '${size.height.round()}',
          },
        );
        final response = await (await client.getUrl(
          uri,
        )).close().timeout(const Duration(seconds: 5));
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) {
          final report = jsonDecode(body) as Map<String, dynamic>;
          if (accepts(report)) return report;
        }
        lastError = body;
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  fail('$label did not render the expected subtitle pixels: $lastError');
}
