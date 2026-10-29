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
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in eventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    }
    eventChannels.clear();
  });

  Future<void> runAsPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> runAsWindows(Future<void> Function() body) async {
    await runAsPlatform(TargetPlatform.windows, body);
  }

  void mockEventChannel(int viewId) {
    final channel = EventChannel('vlc_player/events/$viewId');
    eventChannels.add(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {},
            onCancel: (arguments) {},
          ),
        );
  }

  List<MethodCall> recordPluginCalls() {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          return null;
        });
    return calls;
  }

  testWidgets('creates platform views with player options and fit', (
    WidgetTester tester,
  ) async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      await runAsPlatform(platform, () async {
        recordPluginCalls();
        final platformViews = _PlatformViewsRecorder(onCreate: mockEventChannel)
          ..install();
        final controller = VlcPlayerController(
          options: const <String>['--network-caching=300'],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 320,
              height: 180,
              child: VlcPlayer(controller: controller, fit: VlcVideoFit.fill),
            ),
          ),
        );
        await tester.pump();

        final view = platformViews.createdViews.single;
        expect(view.viewType, 'plugins.lingjhf.com/vlc_player/view');
        expect(view.creationParams?['options'], <String>[
          '--network-caching=300',
        ]);
        expect(view.creationParams?['fit'], 'fill');
        expect(
          find.byType(switch (platform) {
            TargetPlatform.android => AndroidView,
            TargetPlatform.iOS => UiKitView,
            TargetPlatform.macOS => AppKitView,
            _ => throw StateError('Unexpected platform $platform.'),
          }),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  });

  testWidgets('shows an unsupported platform fallback', (
    WidgetTester tester,
  ) async {
    await runAsPlatform(TargetPlatform.fuchsia, () async {
      final controller = VlcPlayerController();

      await tester.pumpWidget(
        MaterialApp(home: VlcPlayer(controller: controller)),
      );

      expect(find.textContaining('currently supports'), findsOneWidget);

      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('replacing a texture controller attaches a new player', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      var nextViewId = 70;
      var nextTextureId = 170;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            if (call.method == 'create') {
              final viewId = nextViewId++;
              mockEventChannel(viewId);
              return <String, Object?>{
                'viewId': viewId,
                'textureId': nextTextureId++,
              };
            }
            return null;
          });
      final first = VlcPlayerController();
      final second = VlcPlayerController();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: VlcPlayer(controller: first),
        ),
      );
      await tester.pump();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 170);
      expect(first.isAttached, isTrue);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: VlcPlayer(controller: second),
        ),
      );
      await tester.pump();

      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 171);
      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);
      expect(calls.map((call) => call.method), <String>['create', 'create']);

      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    });
  });

  testWidgets('late texture creation cannot detach a reused controller', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      final first = VlcPlayerController();
      final second = VlcPlayerController();
      final oldCreate = Completer<Map<String, Object?>>();
      var creates = 0;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            if (call.method == 'create') {
              final id = ++creates;
              if (id == 1) return oldCreate.future;
              mockEventChannel(id);
              return {'viewId': id, 'textureId': id + 100};
            }
            return null;
          });
      Future<void> show(VlcPlayerController controller) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: VlcPlayer(controller: controller),
        ),
      );
      await show(first);
      await tester.pump();
      await show(second);
      await tester.pump();
      await show(first);
      await tester.pump();
      oldCreate.complete({'viewId': 1, 'textureId': 101});
      await tester.pump();
      await tester.pump();
      expect(first.isAttached, isTrue);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 103);
      await first.play();
      expect(calls.last.arguments, {'viewId': 3});
      expect(
        calls
            .where((call) => call.method == 'dispose')
            .map((call) => call.arguments),
        contains(equals({'viewId': 1})),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    });
  });

  testWidgets('a stale platform callback cannot attach to a new controller', (
    WidgetTester tester,
  ) async {
    await runAsPlatform(TargetPlatform.android, () async {
      final calls = recordPluginCalls();
      final platformViews = _PlatformViewsRecorder(onCreate: mockEventChannel)
        ..install();
      final first = VlcPlayerController();
      final second = VlcPlayerController();
      await tester.pumpWidget(MaterialApp(home: VlcPlayer(controller: first)));
      await tester.pump();
      final oldView = tester.widget<AndroidView>(find.byType(AndroidView));
      await tester.pumpWidget(MaterialApp(home: VlcPlayer(controller: second)));
      await tester.pump();
      oldView.onPlatformViewCreated!(999);
      await tester.pump();
      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);
      await second.play();
      expect(calls.last.arguments, {
        'viewId': platformViews.createdViews.last.id,
      });
      expect(
        calls
            .where((call) => call.method == 'dispose')
            .map((call) => call.arguments),
        contains(equals({'viewId': 999})),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    });
  });

  testWidgets('sharing a controller reports ownership without cleanup errors', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      final controller = VlcPlayerController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'create') {
              mockEventChannel(1);
              return {'viewId': 1, 'textureId': 101};
            }
            return null;
          });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(
                width: 200,
                height: 100,
                child: VlcPlayer(controller: controller),
              ),
              SizedBox(
                width: 200,
                height: 100,
                child: VlcPlayer(controller: controller),
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('one VlcPlayer at a time'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });

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

  testWidgets('fits texture players with the configured video fit', (
    WidgetTester tester,
  ) async {
    await runAsWindows(() async {
      final controller = VlcPlayerController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'create') {
              mockEventChannel(8);
              return <String, Object?>{'viewId': 8, 'textureId': 43};
            }
            return null;
          });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: VlcPlayer(controller: controller, fit: VlcVideoFit.cover),
          ),
        ),
      );
      await tester.pump();

      const channel = EventChannel('vlc_player/events/8');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'playing',
              'videoSize': <String, Object?>{'width': 640, 'height': 360},
            }),
            null,
          );
      await tester.pump();

      final fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fittedBox.fit, BoxFit.cover);
      expect(find.byType(Texture), findsOneWidget);

      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

class _PlatformViewsRecorder {
  _PlatformViewsRecorder({required this.onCreate});

  final void Function(int viewId) onCreate;
  final List<_RecordedPlatformView> createdViews = <_RecordedPlatformView>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, _handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'create':
        final arguments = (call.arguments as Map).cast<String, Object?>();
        final id = arguments['id']! as int;
        onCreate(id);
        createdViews.add(
          _RecordedPlatformView(
            id: id,
            viewType: arguments['viewType']! as String,
            creationParams: _decodeCreationParams(arguments['params']),
          ),
        );
        return arguments.containsKey('direction') ? 0 : null;
      case 'resize':
        final arguments = (call.arguments as Map).cast<String, Object?>();
        return <String, Object?>{
          'width': arguments['width'],
          'height': arguments['height'],
        };
      default:
        return null;
    }
  }

  Map<Object?, Object?>? _decodeCreationParams(Object? value) {
    if (value is! Uint8List) {
      return null;
    }
    final decoded = const StandardMessageCodec().decodeMessage(
      ByteData.sublistView(value),
    );
    return (decoded as Map).cast<Object?, Object?>();
  }
}

class _RecordedPlatformView {
  const _RecordedPlatformView({
    required this.id,
    required this.viewType,
    required this.creationParams,
  });

  final int id;
  final String viewType;
  final Map<Object?, Object?>? creationParams;
}
