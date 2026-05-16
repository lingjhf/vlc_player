import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vlc_player/vlc_player.dart';
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
    await _pumpNavigation(tester);
    expect(find.text('MP4 sample video'), findsOneWidget);

    await _popRoute(tester, find.text('MP4 sample video'));
    await tester.tap(find.byKey(const ValueKey<String>('hls-example-tile')));
    await _pumpNavigation(tester);
    expect(find.text('M3U8 sample stream'), findsOneWidget);

    await _popRoute(tester, find.text('M3U8 sample stream'));
    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-example-tile')),
    );
    await _pumpNavigation(tester);
    expect(
      find.byKey(const ValueKey<String>('full-player-play-pause-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('full-player-seek-slider')),
      findsOneWidget,
    );
  });

  testWidgets('native player view can be created', (WidgetTester tester) async {
    if (Platform.isLinux || Platform.isIOS) {
      // Linux libVLC core coverage lives in ctest; the GitHub Xvfb runner is
      // not stable enough for the real Flutter texture view. The iOS
      // simulator can hang while creating an empty native VLC view, so iOS
      // keeps coverage to app-level integration flows in CI.
      return;
    }

    final controller = VlcPlayerController(options: _headlessPlayerOptions());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: VlcPlayer(controller: controller),
            ),
          ),
        ),
      ),
    );

    await _pumpUntil(tester, () => controller.isAttached);
    expect(controller.isAttached, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpNavigation(tester);
  });

  testWidgets('full player orientation control updates the button state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(showPlayer: false));

    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-example-tile')),
    );
    await _pumpNavigation(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('full-player-orientation-button')),
    );
    await _pumpNavigation(tester);

    expect(find.byIcon(Icons.stay_current_portrait), findsOneWidget);
  });
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 40 && !condition(); attempt += 1) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _popRoute(WidgetTester tester, Finder routeContent) async {
  Navigator.of(tester.element(routeContent)).pop();
  await _pumpNavigation(tester);
}

List<String> _headlessPlayerOptions() {
  if (Platform.isLinux) {
    return const <String>['--aout=dummy'];
  }
  return const <String>['--no-audio'];
}
