import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/vlc_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('vlc_player');
  final eventChannels = <EventChannel>[];

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    for (final channel in eventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    }
    eventChannels.clear();
  });

  Future<void> runAsWindows(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  void mockEventChannel(int viewId) {
    final channel = EventChannel('vlc_player/events/$viewId');
    eventChannels.add(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
  }

  testWidgets('shows a loading indicator while a texture is created', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      final controller = VlcPlayerController();
      final createCompleter = Completer<Map<String, Object?>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'create') {
              return createCompleter.future;
            }
            return null;
          });

      await tester.pumpWidget(
        MaterialApp(home: VlcPlayer(controller: controller)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('shows texture creation errors', (WidgetTester tester) async {
    await runAsWindows(() async {
      final controller = VlcPlayerController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'create') {
              throw PlatformException(code: 'create_failed', message: 'failed');
            }
            return null;
          });

      await tester.pumpWidget(
        MaterialApp(home: VlcPlayer(controller: controller)),
      );
      await tester.pump();

      expect(find.textContaining('VlcPlayerException'), findsOneWidget);

      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('shows the texture after native player creation succeeds', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      final controller = VlcPlayerController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'create') {
              mockEventChannel(7);
              return <String, Object?>{'viewId': 7, 'textureId': 42};
            }
            return null;
          });

      await tester.pumpWidget(
        MaterialApp(home: VlcPlayer(controller: controller)),
      );
      await tester.pump();

      final texture = tester.widget<Texture>(find.byType(Texture));
      expect(texture.textureId, 42);

      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
