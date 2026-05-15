import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/vlc_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  final eventChannels = <EventChannel>[];

  setUp(() {
    calls.clear();
    eventChannels.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VlcPlayerController.methodChannel, null);
    for (final channel in eventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    }
  });

  void mockEventChannel(int viewId) {
    final channel = EventChannel('vlc_player/events/$viewId');
    eventChannels.add(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
  }

  group('source setup', () {
    test(
      'setSource before attach is replayed when the platform view is created',
      () async {
        final controller = VlcPlayerController();

        await controller.setSource(Uri.parse('https://example.com/video.mp4'));
        expect(calls, isEmpty);

        mockEventChannel(7);
        await controller.attach(7);

        expect(calls, hasLength(1));
        expect(calls.single.method, 'setSource');
        expect(calls.single.arguments, <String, Object?>{
          'viewId': 7,
          'uri': 'https://example.com/video.mp4',
          'autoPlay': false,
          'httpHeaders': <String, String>{},
        });

        controller.dispose();
      },
    );

    test('HLS source uri is passed through to the native VLC player', () async {
      final controller = VlcPlayerController();
      mockEventChannel(9);
      await controller.attach(9);

      await controller.setSource(
        Uri.parse('https://example.com/live/playlist.m3u8'),
        autoPlay: true,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setSource');
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 9,
        'uri': 'https://example.com/live/playlist.m3u8',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      controller.dispose();
    });
  });

  group('platform view lifecycle', () {
    test('attachTexturePlayer creates a texture backed player', () async {
      final controller = VlcPlayerController(
        source: Uri.parse('https://example.com/video.mp4'),
        autoPlay: true,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'create') {
              mockEventChannel(21);
              return <String, Object?>{'viewId': 21, 'textureId': 99};
            }
            return null;
          });

      final textureId = await controller.attachTexturePlayer();

      expect(textureId, 99);
      expect(calls.map((call) => call.method), <String>['create', 'setSource']);
      expect(calls[0].arguments, <String, Object?>{'options': <String>[]});
      expect(calls[1].arguments, <String, Object?>{
        'viewId': 21,
        'uri': 'https://example.com/video.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      controller.dispose();
    });

    test('attachTexturePlayer reuses an existing texture player', () async {
      final controller = VlcPlayerController();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            mockEventChannel(22);
            return <String, Object?>{'viewId': 22, 'textureId': 100};
          });

      final firstTextureId = await controller.attachTexturePlayer();
      final secondTextureId = await controller.attachTexturePlayer();

      expect(firstTextureId, 100);
      expect(secondTextureId, 100);
      expect(calls.map((call) => call.method), <String>['create']);

      controller.dispose();
    });

    test('detach releases a texture backed player', () async {
      final controller = VlcPlayerController();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'create') {
              mockEventChannel(23);
              return <String, Object?>{'viewId': 23, 'textureId': 101};
            }
            return null;
          });

      await controller.attachTexturePlayer();
      await controller.detach();

      expect(calls.map((call) => call.method), <String>['create', 'dispose']);
      expect(calls[1].arguments, <String, Object?>{'viewId': 23});

      controller.dispose();
    });

    test('attach with the same view id does not replay source', () async {
      final controller = VlcPlayerController(
        source: Uri.parse('https://example.com/video.mp4'),
      );

      mockEventChannel(3);
      await controller.attach(3);
      await controller.attach(3);

      expect(calls.map((call) => call.method), <String>['setSource']);

      controller.dispose();
    });

    test('attach to a new view id disposes the previous native view', () async {
      final controller = VlcPlayerController(
        source: Uri.parse('https://example.com/video.mp4'),
      );

      mockEventChannel(1);
      mockEventChannel(2);
      await controller.attach(1);

      calls.clear();
      await controller.attach(2);

      expect(calls.map((call) => call.method), <String>[
        'dispose',
        'setSource',
      ]);
      expect(calls[0].arguments, <String, Object?>{'viewId': 1});
      expect(calls[1].arguments, <String, Object?>{
        'viewId': 2,
        'uri': 'https://example.com/video.mp4',
        'autoPlay': false,
        'httpHeaders': <String, String>{},
      });

      controller.dispose();
    });

    test('dispose releases the current native view once', () async {
      final controller = VlcPlayerController();
      mockEventChannel(4);
      await controller.attach(4);

      calls.clear();
      controller.dispose();
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(calls.map((call) => call.method), <String>['dispose']);
      expect(calls.single.arguments, <String, Object?>{'viewId': 4});
    });

    test('events arriving after dispose are ignored', () async {
      final controller = VlcPlayerController();
      mockEventChannel(5);
      await controller.attach(5);

      final channel = EventChannel('vlc_player/events/5');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'playing',
            }),
            null,
          );
      expect(controller.value.state, VlcPlaybackState.playing);

      controller.dispose();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'paused',
            }),
            null,
          );
    });
  });

  group('playback controls', () {
    test('commands include the attached view id', () async {
      final controller = VlcPlayerController();
      mockEventChannel(12);
      await controller.attach(12);

      await controller.play();
      await controller.seekTo(const Duration(seconds: 3));
      await controller.setVolume(250);
      await controller.setPlaybackSpeed(1.5);

      expect(calls.map((call) => call.method), <String>[
        'play',
        'seekTo',
        'setVolume',
        'setPlaybackSpeed',
      ]);
      expect(calls[0].arguments, <String, Object?>{'viewId': 12});
      expect(calls[1].arguments, <String, Object?>{
        'viewId': 12,
        'position': 3000,
      });
      expect(calls[2].arguments, <String, Object?>{
        'viewId': 12,
        'volume': 200,
      });
      expect(calls[3].arguments, <String, Object?>{'viewId': 12, 'speed': 1.5});

      controller.dispose();
    });

    test('commands before attach fail clearly', () {
      final controller = VlcPlayerController();

      expect(controller.play, throwsStateError);

      controller.dispose();
    });

    test('negative seek positions fail before reaching native code', () async {
      final controller = VlcPlayerController();
      mockEventChannel(13);
      await controller.attach(13);

      expect(
        () => controller.seekTo(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
      expect(calls, isEmpty);

      controller.dispose();
    });
  });

  group('tracks and media info', () {
    test('gets audio tracks from native player', () async {
      final controller = VlcPlayerController();
      mockEventChannel(31);
      await controller.attach(31);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            return <Object?>[
              <Object?, Object?>{'id': 1, 'name': 'Stereo', 'language': 'en'},
            ];
          });

      final tracks = await controller.getAudioTracks();

      expect(calls.single.method, 'getAudioTracks');
      expect(calls.single.arguments, <String, Object?>{'viewId': 31});
      expect(tracks, const <VlcTrackDescription>[
        VlcTrackDescription(id: 1, name: 'Stereo', language: 'en'),
      ]);

      controller.dispose();
    });

    test('subtitle commands include selected id and uri', () async {
      final controller = VlcPlayerController();
      mockEventChannel(32);
      await controller.attach(32);

      await controller.setAudioTrack(2);
      await controller.setSubtitleTrack(4);
      await controller.disableSubtitle();
      await controller.addSubtitle(Uri.parse('file:///tmp/captions.srt'));

      expect(calls.map((call) => call.method), <String>[
        'setAudioTrack',
        'setSubtitleTrack',
        'disableSubtitle',
        'addSubtitle',
      ]);
      expect(calls[0].arguments, <String, Object?>{'viewId': 32, 'id': 2});
      expect(calls[1].arguments, <String, Object?>{'viewId': 32, 'id': 4});
      expect(calls[2].arguments, <String, Object?>{'viewId': 32});
      expect(calls[3].arguments, <String, Object?>{
        'viewId': 32,
        'uri': 'file:///tmp/captions.srt',
      });

      controller.dispose();
    });

    test('audio track selection rejects negative ids', () async {
      final controller = VlcPlayerController();
      mockEventChannel(33);
      await controller.attach(33);

      expect(() => controller.setAudioTrack(-1), throwsArgumentError);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test('gets subtitle tracks from native player', () async {
      final controller = VlcPlayerController();
      mockEventChannel(35);
      await controller.attach(35);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            return <Object?>[
              <Object?, Object?>{'id': 3, 'name': 'Chinese', 'language': 'zh'},
            ];
          });

      final tracks = await controller.getSubtitleTracks();

      expect(calls.single.method, 'getSubtitleTracks');
      expect(tracks, const <VlcTrackDescription>[
        VlcTrackDescription(id: 3, name: 'Chinese', language: 'zh'),
      ]);

      controller.dispose();
    });

    test('gets media info from native player', () async {
      final controller = VlcPlayerController();
      mockEventChannel(34);
      await controller.attach(34);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            return <Object?, Object?>{
              'title': 'Clip',
              'artist': 'Artist',
              'album': 'Album',
              'duration': 12345,
              'videoTracks': <Object?>[
                <Object?, Object?>{
                  'type': 'video',
                  'codec': 'h264',
                  'width': 1920,
                  'height': 1080,
                },
              ],
              'audioTracks': <Object?>[
                <Object?, Object?>{
                  'type': 'audio',
                  'codec': 'mp4a',
                  'channels': 2,
                  'sampleRate': 48000,
                },
              ],
              'subtitleTracks': <Object?>[
                <Object?, Object?>{
                  'type': 'subtitle',
                  'codec': 'subt',
                  'language': 'zh',
                },
              ],
            };
          });

      final info = await controller.getMediaInfo();

      expect(calls.single.method, 'getMediaInfo');
      expect(info.title, 'Clip');
      expect(info.artist, 'Artist');
      expect(info.album, 'Album');
      expect(info.duration, const Duration(milliseconds: 12345));
      expect(info.videoTracks.single.width, 1920);
      expect(info.videoTracks.single.height, 1080);
      expect(info.audioTracks.single.channels, 2);
      expect(info.audioTracks.single.sampleRate, 48000);
      expect(info.subtitleTracks.single.language, 'zh');

      controller.dispose();
    });
  });
}
