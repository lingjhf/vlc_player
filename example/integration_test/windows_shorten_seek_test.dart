import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';

import 'test_support.dart';

const _media = String.fromEnvironment('VLC_PLAYER_SHORTEN_MEDIA');
const _host = String.fromEnvironment('VLC_PLAYER_AV_HOST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || _media.isEmpty || _host.isEmpty) {
    throw StateError(
      'Windows, a Shorten sample, and an audio host are required.',
    );
  }

  testWidgets('Shorten duration and seeks follow the audible samples', (
    tester,
  ) async {
    final file = File(_media);
    expect(await file.exists(), isTrue, reason: file.path);
    final player = VlcPlayerController();
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 640,
          height: 360,
          child: VlcPlayer(controller: player),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => player.isAttached,
      description: 'Shorten player attachment',
      attempts: nativePlayerAttachmentAttempts,
    );
    await player.setVolume(75);
    await player.setMedia(VlcMediaSource(uri: file.uri), autoPlay: true);
    await pumpUntil(
      tester,
      () =>
          player.value.state == VlcPlaybackState.playing &&
          player.value.duration > Duration.zero,
      description: 'Shorten playback and duration',
      attempts: 120,
    );
    expect(
      player.value.duration.inMilliseconds,
      inInclusiveRange(60400, 60560),
    );

    for (final seconds in [30, 5]) {
      await player.seekTo(Duration(seconds: seconds));
      await pumpUntil(
        tester,
        () =>
            player.value.position.inMilliseconds >= seconds * 1000 &&
            player.value.position.inMilliseconds < (seconds + 3) * 1000,
        description: 'Shorten seek to $seconds seconds',
        attempts: 80,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final client = HttpClient();
      try {
        final uri = Uri.parse('$_host/capture').replace(
          queryParameters: {
            'platform': 'windows',
            'label': 'shorten_seek_$seconds',
            'mode': 'reference',
          },
        );
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
      } finally {
        client.close(force: true);
      }
    }
    await player.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
