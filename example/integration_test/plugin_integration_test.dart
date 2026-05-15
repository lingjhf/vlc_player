import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(showPlayer: false));

    expect(find.text('vlc_player example'), findsOneWidget);
    expect(find.text('Video file'), findsOneWidget);
    expect(find.text('HLS stream'), findsOneWidget);
    expect(find.text('Full player'), findsOneWidget);
  });

  testWidgets('example pages can be opened from the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(showPlayer: false));

    await tester.tap(find.byKey(const ValueKey<String>('video-example-tile')));
    await tester.pumpAndSettle();
    expect(find.text('MP4 sample video'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('hls-example-tile')));
    await tester.pumpAndSettle();
    expect(find.text('M3U8 sample stream'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-example-tile')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('full-player-play-pause-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('full-player-seek-slider')),
      findsOneWidget,
    );
  });

  testWidgets('video and HLS pages create the native player view', (
    WidgetTester tester,
  ) async {
    final sources = await _createTestSources();
    await tester.pumpWidget(
      MyApp(videoSource: sources.video, hlsSource: sources.hls),
    );

    await tester.tap(find.byKey(const ValueKey<String>('video-example-tile')));
    await tester.pumpAndSettle();
    expect(find.text('MP4 sample video'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('hls-example-tile')));
    await tester.pumpAndSettle();
    expect(find.text('M3U8 sample stream'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('vlc_player example'), findsOneWidget);
  });

  testWidgets('full player orientation control updates the button state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(showPlayer: false));

    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-example-tile')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-orientation-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stay_current_portrait), findsOneWidget);
  });
}

Future<_TestSources> _createTestSources() async {
  final directory = await Directory.systemTemp.createTemp(
    'vlc_player_integration_',
  );
  final video = File('${directory.path}/sample.mp4');
  final hls = File('${directory.path}/playlist.m3u8');

  await video.writeAsBytes(const <int>[]);
  await hls.writeAsString('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-ENDLIST\n');

  return _TestSources(video.uri, hls.uri);
}

class _TestSources {
  const _TestSources(this.video, this.hls);

  final Uri video;
  final Uri hls;
}
