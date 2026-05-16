import 'dart:async';

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

    test(
      'setMedia restores previous source when native loading fails',
      () async {
        final controller = VlcPlayerController();
        mockEventChannel(11);
        await controller.attach(11);
        var failSetSource = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
              call,
            ) async {
              calls.add(call);
              if (failSetSource && call.method == 'setSource') {
                throw PlatformException(
                  code: VlcPlayerErrorCode.setSourceFailed,
                  message: 'Could not load source.',
                );
              }
              return null;
            });

        final first = VlcMediaSource(
          uri: Uri.parse('https://example.com/first.mp4'),
        );
        final second = VlcMediaSource(
          uri: Uri.parse('https://example.com/second.mp4'),
        );

        await controller.setMedia(first, autoPlay: true);
        calls.clear();
        failSetSource = true;

        await expectLater(
          controller.setMedia(second),
          throwsA(isA<VlcPlayerException>()),
        );

        expect(calls.single.method, 'setSource');
        expect(controller.currentMediaSource, first);
        expect(controller.playlist, isEmpty);
        expect(controller.playlistIndex, isNull);

        controller.dispose();
      },
    );

    test('pending source keeps an immutable headers snapshot', () async {
      final controller = VlcPlayerController();
      final headers = <String, String>{'Authorization': 'Bearer one'};

      await controller.setSource(
        Uri.parse('https://example.com/video.mp4'),
        httpHeaders: headers,
      );
      headers['Authorization'] = 'Bearer two';

      mockEventChannel(10);
      await controller.attach(10);

      expect(calls.single.method, 'setSource');
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 10,
        'uri': 'https://example.com/video.mp4',
        'autoPlay': false,
        'httpHeaders': <String, String>{'Authorization': 'Bearer one'},
      });

      controller.dispose();
    });

    test('setMedia before attach replays full source arguments', () async {
      final controller = VlcPlayerController();

      await controller.setMedia(
        VlcMediaSource(
          uri: Uri.parse('https://example.com/video.mp4'),
          httpHeaders: const <String, String>{'Authorization': 'Bearer one'},
          mediaOptions: const <String>[':network-caching=1200'],
          startPosition: const Duration(seconds: 5),
        ),
        autoPlay: true,
      );
      expect(calls, isEmpty);

      mockEventChannel(8);
      await controller.attach(8);

      expect(calls.single.method, 'setSource');
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 8,
        'uri': 'https://example.com/video.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{'Authorization': 'Bearer one'},
        'mediaOptions': <String>[':network-caching=1200'],
        'startPosition': 5000,
      });

      controller.dispose();
    });

    test(
      'constructor accepts mediaSource and replays full source arguments',
      () async {
        final controller = VlcPlayerController(
          mediaSource: VlcMediaSource(
            uri: Uri.parse('https://example.com/video.mp4'),
            httpHeaders: const <String, String>{'Authorization': 'Bearer one'},
            mediaOptions: const <String>[':network-caching=1200'],
            startPosition: const Duration(seconds: 5),
          ),
          autoPlay: true,
        );

        mockEventChannel(6);
        await controller.attach(6);

        expect(controller.httpHeaders, <String, String>{
          'Authorization': 'Bearer one',
        });
        expect(calls.single.method, 'setSource');
        expect(calls.single.arguments, <String, Object?>{
          'viewId': 6,
          'uri': 'https://example.com/video.mp4',
          'autoPlay': true,
          'httpHeaders': <String, String>{'Authorization': 'Bearer one'},
          'mediaOptions': <String>[':network-caching=1200'],
          'startPosition': 5000,
        });

        controller.dispose();
      },
    );

    test('constructor rejects empty source uri', () {
      expect(() => VlcPlayerController(source: Uri()), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('constructor rejects source and mediaSource together', () {
      expect(
        () => VlcPlayerController(
          source: Uri.parse('https://example.com/video.mp4'),
          mediaSource: VlcMediaSource(
            uri: Uri.parse('https://example.com/other.mp4'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isEmpty);
    });

    test('constructor keeps immutable options and headers snapshots', () async {
      final options = <String>['--network-caching=1000'];
      final headers = <String, String>{'Authorization': 'Bearer one'};
      final controller = VlcPlayerController(
        source: Uri.parse('https://example.com/video.mp4'),
        autoPlay: true,
        options: options,
        httpHeaders: headers,
      );

      options.add('--file-caching=1000');
      headers['Authorization'] = 'Bearer two';

      expect(
        () => controller.options.add('--no-video-title-show'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => controller.httpHeaders['X-Test'] = 'value',
        throwsA(isA<UnsupportedError>()),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'create') {
              mockEventChannel(11);
              return <String, Object?>{'viewId': 11, 'textureId': 91};
            }
            return null;
          });

      await controller.attachTexturePlayer();

      expect(calls.map((call) => call.method), <String>['create', 'setSource']);
      expect(calls[0].arguments, <String, Object?>{
        'options': <String>['--network-caching=1000'],
      });
      expect(calls[1].arguments, <String, Object?>{
        'viewId': 11,
        'uri': 'https://example.com/video.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{'Authorization': 'Bearer one'},
      });

      controller.dispose();
    });

    test('empty source uri fails before reaching native code', () async {
      final controller = VlcPlayerController();

      expect(() => controller.setSource(Uri()), throwsArgumentError);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test(
      'attach disposes the new platform view if disposed while replacing old view',
      () async {
        final controller = VlcPlayerController();
        mockEventChannel(41);
        await controller.attach(41);

        final oldDisposeStarted = Completer<void>();
        final oldDisposeCompleter = Completer<void>();
        calls.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
              call,
            ) async {
              calls.add(call);
              final arguments = call.arguments as Map<Object?, Object?>;
              if (call.method == 'dispose' && arguments['viewId'] == 41) {
                oldDisposeStarted.complete();
                await oldDisposeCompleter.future;
              }
              return null;
            });

        final attach = controller.attach(42);
        await oldDisposeStarted.future;
        controller.dispose();
        oldDisposeCompleter.complete();

        await expectLater(attach, throwsStateError);
        expect(calls.map((call) => call.method), <String>[
          'dispose',
          'dispose',
        ]);
        expect(calls[0].arguments, <String, Object?>{'viewId': 41});
        expect(calls[1].arguments, <String, Object?>{'viewId': 42});
      },
    );
  });

  group('playlist', () {
    test('setPlaylist before attach replays the selected source', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(
          uri: Uri.parse('https://example.com/two.mp4'),
          mediaOptions: const <String>[':network-caching=1500'],
          startPosition: const Duration(seconds: 4),
        ),
      ];

      await controller.setPlaylist(sources, initialIndex: 1, autoPlay: true);
      expect(calls, isEmpty);
      expect(controller.playlist, sources);
      expect(controller.playlistIndex, 1);
      expect(controller.currentMediaSource, sources[1]);
      expect(controller.hasNext, isFalse);
      expect(controller.hasPrevious, isTrue);

      mockEventChannel(51);
      await controller.attach(51);

      expect(calls.single.method, 'setSource');
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 51,
        'uri': 'https://example.com/two.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
        'mediaOptions': <String>[':network-caching=1500'],
        'startPosition': 4000,
      });
      expect(controller.playlist, sources);
      expect(controller.playlistIndex, 1);
      expect(controller.currentMediaSource, sources[1]);
      expect(controller.hasNext, isFalse);
      expect(controller.hasPrevious, isTrue);

      controller.dispose();
    });

    test(
      'setPlaylist before texture attach preserves playlist after replay',
      () async {
        final controller = VlcPlayerController();
        final sources = <VlcMediaSource>[
          VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
          VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
        ];

        await controller.setPlaylist(sources, initialIndex: 1, autoPlay: true);
        expect(calls, isEmpty);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
              call,
            ) async {
              calls.add(call);
              if (call.method == 'create') {
                mockEventChannel(61);
                return <String, Object?>{'viewId': 61, 'textureId': 161};
              }
              return null;
            });

        await controller.attachTexturePlayer();

        expect(calls.map((call) => call.method), <String>[
          'create',
          'setSource',
        ]);
        expect(calls[1].arguments, <String, Object?>{
          'viewId': 61,
          'uri': 'https://example.com/two.mp4',
          'autoPlay': true,
          'httpHeaders': <String, String>{},
        });
        expect(controller.playlist, sources);
        expect(controller.playlistIndex, 1);
        expect(controller.currentMediaSource, sources[1]);
        expect(controller.hasNext, isFalse);
        expect(controller.hasPrevious, isTrue);

        controller.dispose();
      },
    );

    test(
      'setPlaylist rejects empty lists and invalid initial indexes',
      () async {
        final controller = VlcPlayerController();
        final sources = <VlcMediaSource>[
          VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        ];

        await expectLater(
          controller.setPlaylist(const <VlcMediaSource>[]),
          throwsArgumentError,
        );
        await expectLater(
          controller.setPlaylist(sources, initialIndex: -1),
          throwsRangeError,
        );
        await expectLater(
          controller.setPlaylist(sources, initialIndex: 1),
          throwsRangeError,
        );
        expect(calls, isEmpty);

        controller.dispose();
      },
    );

    test('next and previous load playlist items and report bounds', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(52);
      await controller.attach(52);
      await controller.setPlaylist(sources);
      calls.clear();

      expect(await controller.next(), isTrue);
      expect(controller.playlistIndex, 1);
      expect(controller.hasNext, isFalse);
      expect(controller.hasPrevious, isTrue);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 52,
        'uri': 'https://example.com/two.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      calls.clear();
      expect(await controller.next(), isFalse);
      expect(calls, isEmpty);

      expect(await controller.previous(autoPlay: false), isTrue);
      expect(controller.playlistIndex, 0);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 52,
        'uri': 'https://example.com/one.mp4',
        'autoPlay': false,
        'httpHeaders': <String, String>{},
      });

      calls.clear();
      expect(await controller.previous(), isFalse);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test('next restores playlist state when native loading fails', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(55);
      await controller.attach(55);
      await controller.setPlaylist(sources);
      calls.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'dispose') {
              return null;
            }
            throw PlatformException(
              code: VlcPlayerErrorCode.setSourceFailed,
              message: 'failed',
            );
          });

      await expectLater(controller.next(), throwsA(isA<VlcPlayerException>()));
      expect(controller.playlistIndex, 0);
      expect(controller.currentMediaSource, sources[0]);

      controller.dispose();
    });

    test(
      'setPlaylist restores previous playlist when native loading fails',
      () async {
        final controller = VlcPlayerController();
        final first = <VlcMediaSource>[
          VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        ];
        final second = <VlcMediaSource>[
          VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
        ];

        mockEventChannel(56);
        await controller.attach(56);
        await controller.setPlaylist(first);
        calls.clear();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
              call,
            ) async {
              calls.add(call);
              if (call.method == 'dispose') {
                return null;
              }
              throw PlatformException(
                code: VlcPlayerErrorCode.setSourceFailed,
                message: 'failed',
              );
            });

        await expectLater(
          controller.setPlaylist(second),
          throwsA(isA<VlcPlayerException>()),
        );
        expect(controller.playlist, first);
        expect(controller.playlistIndex, 0);
        expect(controller.currentMediaSource, first[0]);

        controller.dispose();
      },
    );

    test('next and previous require a playlist', () async {
      final controller = VlcPlayerController();

      await expectLater(controller.next(), throwsStateError);
      await expectLater(controller.previous(), throwsStateError);

      controller.dispose();
    });

    test('setSource clears playlist state', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      await controller.setPlaylist(sources);
      await controller.setSource(Uri.parse('https://example.com/single.mp4'));

      expect(controller.playlist, isEmpty);
      expect(controller.playlistIndex, isNull);
      expect(controller.hasNext, isFalse);
      expect(controller.hasPrevious, isFalse);
      expect(
        controller.currentMediaSource!.uri,
        Uri.parse('https://example.com/single.mp4'),
      );

      controller.dispose();
    });

    test('setSource restores playlist when native loading fails', () async {
      final controller = VlcPlayerController();
      mockEventChannel(52);
      await controller.attach(52);
      var failSetSource = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (failSetSource && call.method == 'setSource') {
              throw PlatformException(
                code: VlcPlayerErrorCode.setSourceFailed,
                message: 'Could not load source.',
              );
            }
            return null;
          });
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];
      await controller.setPlaylist(sources, initialIndex: 1);
      calls.clear();
      failSetSource = true;

      await expectLater(
        controller.setSource(Uri.parse('https://example.com/single.mp4')),
        throwsA(isA<VlcPlayerException>()),
      );

      expect(calls.single.method, 'setSource');
      expect(controller.playlist, sources);
      expect(controller.playlistIndex, 1);
      expect(controller.currentMediaSource, sources[1]);

      controller.dispose();
    });

    test('ended events auto advance once to the next playlist item', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(53);
      await controller.attach(53);
      await controller.setPlaylist(sources, autoAdvance: true);
      calls.clear();

      final channel = EventChannel('vlc_player/events/53');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playlistIndex, 1);
      expect(calls.single.method, 'setSource');
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 53,
        'uri': 'https://example.com/two.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      calls.clear();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playlistIndex, 1);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test('auto advance reports native loading failures', () async {
      var failSetSource = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (failSetSource && call.method == 'setSource') {
              throw PlatformException(
                code: VlcPlayerErrorCode.setSourceFailed,
                message: 'Could not load playlist item.',
              );
            }
            return null;
          });

      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(60);
      await controller.attach(60);
      await controller.setPlaylist(sources, autoAdvance: true);
      calls.clear();
      failSetSource = true;

      final channel = EventChannel('vlc_player/events/60');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await pumpEventQueue();

      expect(controller.playlistIndex, 0);
      expect(controller.value.state, VlcPlaybackState.error);
      expect(controller.value.error?.code, VlcPlayerErrorCode.setSourceFailed);
      expect(
        controller.value.errorDescription,
        'Could not load playlist item.',
      );

      controller.dispose();
    });

    test('autoAdvance can be disabled', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(54);
      await controller.attach(54);
      await controller.setPlaylist(sources, autoAdvance: false);
      calls.clear();

      final channel = EventChannel('vlc_player/events/54');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playlistIndex, 0);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test('loopAll wraps manual next and previous at playlist bounds', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(57);
      await controller.attach(57);
      await controller.setPlaylist(
        sources,
        initialIndex: 1,
        loopMode: VlcPlaylistLoopMode.loopAll,
      );
      calls.clear();

      expect(await controller.next(), isTrue);
      expect(controller.playlistIndex, 0);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 57,
        'uri': 'https://example.com/one.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      calls.clear();
      expect(await controller.previous(), isTrue);
      expect(controller.playlistIndex, 1);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 57,
        'uri': 'https://example.com/two.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      controller.dispose();
    });

    test('ended events wrap to the first item in loopAll mode', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
        VlcMediaSource(uri: Uri.parse('https://example.com/two.mp4')),
      ];

      mockEventChannel(58);
      await controller.attach(58);
      await controller.setPlaylist(
        sources,
        initialIndex: 1,
        loopMode: VlcPlaylistLoopMode.loopAll,
      );
      calls.clear();

      final channel = EventChannel('vlc_player/events/58');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playlistIndex, 0);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 58,
        'uri': 'https://example.com/one.mp4',
        'autoPlay': true,
        'httpHeaders': <String, String>{},
      });

      controller.dispose();
    });

    test('ended events reload the current item in loopOne mode', () async {
      final controller = VlcPlayerController();
      final sources = <VlcMediaSource>[
        VlcMediaSource(uri: Uri.parse('https://example.com/one.mp4')),
      ];

      mockEventChannel(59);
      await controller.attach(59);
      await controller.setPlaylist(
        sources,
        loopMode: VlcPlaylistLoopMode.loopOne,
      );
      calls.clear();

      final channel = EventChannel('vlc_player/events/59');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeSuccessEnvelope(<String, Object?>{
              'state': 'ended',
            }),
            null,
          );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playlistIndex, 0);
      expect(calls.single.arguments, <String, Object?>{
        'viewId': 59,
        'uri': 'https://example.com/one.mp4',
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

    test(
      'attachTexturePlayer releases native player if disposed during create',
      () async {
        final controller = VlcPlayerController();
        final createStarted = Completer<void>();
        final createCompleter = Completer<void>();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
              call,
            ) async {
              calls.add(call);
              if (call.method == 'create') {
                createStarted.complete();
                await createCompleter.future;
                return <String, Object?>{'viewId': 24, 'textureId': 102};
              }
              return null;
            });

        final attach = controller.attachTexturePlayer();
        await createStarted.future;
        controller.dispose();
        createCompleter.complete();

        await expectLater(attach, throwsStateError);
        expect(calls.map((call) => call.method), <String>['create', 'dispose']);
        expect(calls.last.arguments, <String, Object?>{'viewId': 24});
      },
    );

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

    test(
      'non-finite playback speeds fail before reaching native code',
      () async {
        final controller = VlcPlayerController();
        mockEventChannel(14);
        await controller.attach(14);

        expect(
          () => controller.setPlaybackSpeed(double.nan),
          throwsArgumentError,
        );
        expect(
          () => controller.setPlaybackSpeed(double.infinity),
          throwsArgumentError,
        );
        expect(calls, isEmpty);

        controller.dispose();
      },
    );

    test('native command errors are wrapped as VlcPlayerException', () async {
      final controller = VlcPlayerController();
      mockEventChannel(15);
      await controller.attach(15);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VlcPlayerController.methodChannel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'dispose') {
              return null;
            }
            throw PlatformException(
              code: VlcPlayerErrorCode.playerNotFound,
              message: 'No player',
              details: <String, Object?>{'viewId': 15},
            );
          });

      await expectLater(
        controller.play(),
        throwsA(
          isA<VlcPlayerException>()
              .having(
                (error) => error.code,
                'code',
                VlcPlayerErrorCode.playerNotFound,
              )
              .having((error) => error.message, 'message', 'No player')
              .having((error) => error.details, 'details', <String, Object?>{
                'viewId': 15,
              }),
        ),
      );

      controller.dispose();
    });
  });

  group('event errors', () {
    test('event channel errors update the structured player error', () async {
      final controller = VlcPlayerController();
      mockEventChannel(16);
      await controller.attach(16);

      final channel = EventChannel('vlc_player/events/16');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeErrorEnvelope(
              code: VlcPlayerErrorCode.playbackError,
              message: 'Playback failed',
              details: <String, Object?>{'viewId': 16},
            ),
            null,
          );

      expect(controller.value.state, VlcPlaybackState.error);
      expect(controller.value.error!.code, VlcPlayerErrorCode.playbackError);
      expect(controller.value.error!.message, 'Playback failed');
      expect(controller.value.error!.details, <String, Object?>{'viewId': 16});
      expect(controller.value.errorDescription, 'Playback failed');

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

    test('subtitle track selection rejects negative ids', () async {
      final controller = VlcPlayerController();
      mockEventChannel(36);
      await controller.attach(36);

      expect(() => controller.setSubtitleTrack(-1), throwsArgumentError);
      expect(calls, isEmpty);

      controller.dispose();
    });

    test('empty subtitle uri fails before reaching native code', () async {
      final controller = VlcPlayerController();
      mockEventChannel(37);
      await controller.attach(37);

      expect(() => controller.addSubtitle(Uri()), throwsArgumentError);
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
