import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');
const _first = String.fromEnvironment('VLC_PLAYER_TRACKER_FIRST');
const _second = String.fromEnvironment('VLC_PLAYER_TRACKER_SECOND');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows ||
      _host.isEmpty ||
      _first.isEmpty ||
      _second.isEmpty) {
    throw StateError(
      'Windows, two tracker files and an audio host are required.',
    );
  }
  testWidgets('simultaneous tracker players retain independent audio', (
    tester,
  ) async {
    final first = VlcPlayerController();
    final second = VlcPlayerController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget view(bool includeFirst) => MaterialApp(
      home: Row(
        children: [
          if (includeFirst)
            SizedBox(
              key: const ValueKey('first'),
              width: 320,
              height: 180,
              child: VlcPlayer(controller: first),
            ),
          SizedBox(
            key: const ValueKey('second'),
            width: 320,
            height: 180,
            child: VlcPlayer(controller: second),
          ),
        ],
      ),
    );
    expect(await File(_first).exists(), isTrue);
    expect(await File(_second).exists(), isTrue);
    await tester.pumpWidget(view(true));
    await pumpUntil(
      tester,
      () => first.isAttached && second.isAttached,
      description: 'both tracker players attached',
      attempts: nativePlayerAttachmentAttempts,
    );
    await first.setVolume(75);
    await second.setVolume(0);
    await Future.wait([
      first.setMedia(VlcMediaSource(uri: File(_first).uri), autoPlay: true),
      second.setMedia(VlcMediaSource(uri: File(_second).uri), autoPlay: true),
    ]);
    await pumpUntil(
      tester,
      () =>
          first.value.state == VlcPlaybackState.playing &&
          second.value.state == VlcPlaybackState.playing,
      description: 'both tracker players playing',
      attempts: 80,
    );
    await first.setVolume(75);
    await second.setVolume(0);
    await _expectTone(tester, 'tracker_first', 436, 583);
    await first.setVolume(0);
    await second.setVolume(75);
    await _expectTone(tester, 'tracker_second', 583, 436);
    await tester.pumpWidget(view(false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    await _expectTone(tester, 'tracker_after_detach', 583, 436);
    await second.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Future<void> _expectTone(
  WidgetTester tester,
  String label,
  int frequency,
  int rejectFrequency,
) async {
  await tester.pump(const Duration(milliseconds: 800));
  final client = HttpClient();
  try {
    final uri = Uri.parse('$_host/capture').replace(
      queryParameters: {
        'platform': 'windows',
        'label': label,
        'frequency': '$frequency',
        'reject_frequency': '$rejectFrequency',
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
