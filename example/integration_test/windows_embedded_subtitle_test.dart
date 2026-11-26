import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _manifest = String.fromEnvironment('VLC_PLAYER_SUBTITLE_MANIFEST');
const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _manifest.isEmpty || _host.isEmpty) {
    throw StateError(
      'Windows, an embedded subtitle manifest and host are required.',
    );
  }
  final cases = (jsonDecode(File(_manifest).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (cases.isEmpty) throw StateError('Subtitle manifest is empty.');
  for (final item in cases) {
    final name = item['name'] as String;
    testWidgets('embedded subtitle: $name', (tester) async {
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
        VlcMediaSource(uri: File(item['path'] as String).uri),
        autoPlay: true,
      );
      await pumpUntil(
        tester,
        () => controller.value.videoSize != null,
        description: '$name video dimensions',
        attempts: 80,
      );
      List<VlcTrackDescription> tracks = [];
      for (var i = 0; i < 40; i++) {
        tracks = (await controller.getSubtitleTracks())
            .where((t) => t.id >= 0)
            .toList();
        if (tracks.isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tracks, isNotEmpty, reason: '$name embedded track not discovered');
      await controller.disableSubtitle();
      final redOnGreen = item['red_on_green'] == true;
      final colorOnRed = item['color_on_red'] == true;
      final defaultDvbPalette = item['default_dvb_palette'] == true;
      final paletteReference = item['palette_reference'] == true;
      final baseline = await _picture(
        tester,
        controller,
        '${name}_disabled',
        (r) => paletteReference
            ? (r['gray_background_fraction'] as num) > .98
            : redOnGreen
            ? (r['green_fraction'] as num) > .9 && (r['red_pixels'] as num) < 5
            : (r['red_fraction'] as num) > .9 &&
                  (colorOnRed
                      ? (r['non_red_pixels'] as num) < 5
                      : (r['neutral_fraction'] as num) < .001),
      );
      if (item['refresh_on_select'] == true) {
        await pumpUntil(
          tester,
          () => controller.value.position >= const Duration(seconds: 1),
          description: '$name progress before subtitle selection',
          attempts: 40,
        );
      }
      final selectionDelayMs = item['selection_delay_ms'] as int? ?? 0;
      if (selectionDelayMs > 0) {
        await tester.pump(Duration(milliseconds: selectionDelayMs));
      }
      await controller.setSubtitleTrack(tracks.first.id);
      if (item['refresh_on_select'] == true) {
        final position = controller.value.position;
        await controller.seekTo(position);
        // ignore: avoid_print
        print('SUBTITLE_REFRESH_POSITION $name ${position.inMilliseconds}');
      }
      bool isVisible(Map<String, dynamic> r) => paletteReference
          ? r['palette_reference_passed'] == true
          : redOnGreen
          ? (r['green_fraction'] as num) > .75 &&
                (r['red_pixels'] as num) > 50 &&
                (r['blue_pixels'] as num) < 5
          : (r['red_fraction'] as num) > .75 &&
                (colorOnRed
                    ? (r['non_red_pixels'] as num) > 50 &&
                          (!defaultDvbPalette ||
                              ((r['green_fraction'] as num) > .001 &&
                                  (r['dark_blue_pixels'] as num) > 10))
                    : (r['neutral_pixels'] as num) > 50 &&
                          (r['neutral_fraction'] as num) >
                              (baseline['neutral_fraction'] as num) + .001);
      final visible = await _picture(
        tester,
        controller,
        '${name}_selected',
        isVisible,
        paletteReference: paletteReference ? name : null,
      );
      final selectedHoldMs = item['selected_hold_ms'] as int? ?? 0;
      if (selectedHoldMs > 0) {
        await tester.pump(Duration(milliseconds: selectedHoldMs));
        await _picture(
          tester,
          controller,
          '${name}_selected_later',
          isVisible,
          paletteReference: paletteReference ? name : null,
        );
      }
      await controller.disableSubtitle();
      await _picture(
        tester,
        controller,
        '${name}_disabled_again',
        (r) => paletteReference
            ? (r['gray_background_fraction'] as num) > .98
            : redOnGreen
            ? (r['green_fraction'] as num) > .9 && (r['red_pixels'] as num) < 5
            : (r['red_fraction'] as num) > .9 &&
                  (colorOnRed
                      ? (r['non_red_pixels'] as num) < 5
                      : (r['neutral_fraction'] as num) < .001),
      );
      await controller.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // ignore: avoid_print
      print('EMBEDDED_SUBTITLE_PASS $name ${tracks.first.id} $visible');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

Future<Map<String, dynamic>> _picture(
  WidgetTester tester,
  VlcPlayerController controller,
  String label,
  bool Function(Map<String, dynamic>) accepts, {
  String? paletteReference,
}) async {
  final client = HttpClient();
  Object? lastError;
  try {
    for (var attempt = 0; attempt < 80; attempt++) {
      await tester.pump(const Duration(milliseconds: 150));
      try {
        final size = controller.value.videoSize!;
        final query = <String, String>{
          'label': label,
          'width': '${size.width.round()}',
          'height': '${size.height.round()}',
        };
        if (paletteReference != null) {
          query['palette_reference'] = paletteReference;
        }
        final uri = Uri.parse(
          '$_host/subtitle-picture',
        ).replace(queryParameters: query);
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
  fail('$label did not render expected pixels: $lastError');
}
