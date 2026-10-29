import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/src/vlc_player_controller_internals.dart';
import 'package:vlc_player/vlc_player.dart';

import 'vlc_method_channel_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VlcMethodChannelHarness harness;
  late VlcPlayerController controller;

  final a = VlcMediaSource(uri: Uri.parse('https://example.com/a.mp4'));
  final b = VlcMediaSource(uri: Uri.parse('https://example.com/b.mp4'));
  final c = VlcMediaSource(uri: Uri.parse('https://example.com/c.mp4'));

  setUp(() {
    harness = VlcMethodChannelHarness()..install();
    controller = VlcPlayerController();
  });
  tearDown(() async {
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    harness.dispose();
  });

  test('a controller rejects two simultaneous widget owners', () async {
    final internals = controller as VlcPlayerControllerInternals;
    final first = internals.createBinding();
    expect(internals.createBinding, throwsStateError);
    await first.dispose();
    final replacement = internals.createBinding();
    expect(replacement.isDisposed, isFalse);
    await first.dispose();
    expect(replacement.isDisposed, isFalse);
  });

  test('overlapping texture attachments share one native create', () async {
    final started = Completer<void>();
    final response = Completer<Object?>();
    harness.mockEventChannel(1);
    harness.install(
      onCall: (call) async {
        if (call.method == 'create') {
          started.complete();
          return response.future;
        }
        return null;
      },
    );
    final first = harness.attachTexturePlayer(controller);
    final second = harness.attachTexturePlayer(controller);
    await started.future;
    response.complete({'viewId': 1, 'textureId': 101});
    expect(await Future.wait([first, second]), [101, 101]);
    await harness.detachController(controller);
    expect(harness.calls.map((call) => call.method), ['create', 'dispose']);
  });

  test('a late create releases itself without detaching a new owner', () async {
    final started = Completer<void>();
    final oldCreate = Completer<Object?>();
    var creates = 0;
    harness.mockEventChannel(2);
    harness.install(
      onCall: (call) async {
        if (call.method == 'create') {
          if (++creates == 1) {
            started.complete();
            return oldCreate.future;
          }
          return {'viewId': 2, 'textureId': 102};
        }
        return null;
      },
    );
    final oldBinding = harness.bindingFor(controller);
    final oldOutcome = capture(oldBinding.attachTexturePlayer());
    await started.future;
    await oldBinding.dispose();
    expect(await harness.attachTexturePlayer(controller), 102);
    oldCreate.complete({'viewId': 1, 'textureId': 101});
    expect(await oldOutcome, isA<StateError>());
    await oldBinding.dispose();
    expect(controller.isAttached, isTrue);
    await controller.play();
    expect(harness.calls.last.arguments, {'viewId': 2});
    expect(
      harness.calls
          .where((call) => call.method == 'dispose')
          .map((call) => call.arguments),
      [
        {'viewId': 1},
      ],
    );
  });

  test('a late PlatformView callback only releases its own view', () async {
    final oldBinding = harness.bindingFor(controller);
    await oldBinding.dispose();
    harness.mockEventChannel(2);
    await harness.attachController(controller, 2);
    await expectLater(oldBinding.attach(1), throwsStateError);
    expect(controller.isAttached, isTrue);
    await controller.play();
    expect(harness.calls.map((call) => call.method), ['dispose', 'play']);
    expect(harness.calls.first.arguments, {'viewId': 1});
    expect(harness.calls.last.arguments, {'viewId': 2});
  });

  test('source replay failure releases the player and permits retry', () async {
    var failSource = true;
    var nextId = 0;
    harness.install(
      onCall: (call) async {
        if (call.method == 'create') {
          final id = ++nextId;
          harness.mockEventChannel(id);
          return {'viewId': id, 'textureId': id + 100};
        }
        if (call.method == 'setSource' && failSource) {
          throw PlatformException(code: 'set_source_failed');
        }
        return null;
      },
    );
    await controller.setMedia(a);
    await expectLater(
      harness.attachTexturePlayer(controller),
      throwsA(isA<VlcPlayerException>()),
    );
    expect(controller.isAttached, isFalse);
    expect(harness.calls.last.method, 'dispose');
    failSource = false;
    expect(await harness.attachTexturePlayer(controller), 102);
    expect(controller.currentMediaSource, a);
  });

  final changes = <String, Future<void> Function(VlcPlayerController)>{
    'next': (player) => player.next().then((_) {}),
    'setMedia': (player) => player.setMedia(b),
    'setPlaylist': (player) => player.setPlaylist([b, c]),
    'remove current': (player) => player.removeFromPlaylistAt(0),
    'clearPlaylist': (player) => player.clearPlaylist(),
  };
  for (final change in changes.entries) {
    test(
      '${change.key} rolls back before a newer media change starts',
      () async {
        final started = Completer<void>();
        final pending = Completer<Object?>();
        var block = false;
        harness.mockEventChannel(1);
        harness.install(
          onCall: (call) async {
            if (block &&
                (call.method == 'setSource' || call.method == 'stop')) {
              block = false;
              started.complete();
              return pending.future;
            }
            return null;
          },
        );
        await harness.attachController(controller, 1);
        await controller.setPlaylist([a, b]);
        block = true;
        final oldOutcome = capture(change.value(controller));
        await started.future;
        final newer = controller.setMedia(c);
        await Future<void>.delayed(Duration.zero);
        expect(
          harness.calls.where(
            (call) =>
                call.method == 'setSource' &&
                (call.arguments as Map)['uri'] == c.uri.toString(),
          ),
          isEmpty,
        );
        pending.completeError(PlatformException(code: 'load_failed'));
        expect(await oldOutcome, isA<VlcPlayerException>());
        await newer;
        expect(controller.currentMediaSource, c);
        expect(controller.playlist, isEmpty);
        expect(controller.playlistIndex, isNull);
      },
    );
  }

  test('two failed changes restore the last successful state', () async {
    final started = Completer<void>();
    final pending = Completer<Object?>();
    var fail = false;
    harness.mockEventChannel(1);
    harness.install(
      onCall: (call) async {
        if (fail && call.method == 'setSource') {
          if (!started.isCompleted) {
            started.complete();
            return pending.future;
          }
          throw PlatformException(code: 'second_load_failed');
        }
        return null;
      },
    );
    await harness.attachController(controller, 1);
    await controller.setPlaylist([a, b]);
    fail = true;
    final first = capture(controller.next());
    await started.future;
    final second = capture(controller.setMedia(c));
    pending.completeError(PlatformException(code: 'first_load_failed'));
    expect(await first, isA<VlcPlayerException>());
    expect(await second, isA<VlcPlayerException>());
    expect(controller.currentMediaSource, a);
    expect(controller.playlist, [a, b]);
    expect(controller.playlistIndex, 0);
  });

  test('queued appends use the playlist length when they execute', () async {
    await controller.setPlaylist([a]);
    await Future.wait([
      controller.addToPlaylist(b),
      controller.addToPlaylist(c),
    ]);
    expect(controller.playlist, [a, b, c]);
    expect(controller.currentMediaSource, a);
  });

  test('setPlaylist snapshots input before queued execution', () async {
    final sources = [a, b];
    final operation = controller.setPlaylist(sources);
    sources.clear();
    await operation;
    expect(controller.playlist, [a, b]);
  });

  test('queued media changes are not sent after controller disposal', () async {
    final pending = Completer<Object?>();
    final started = Completer<void>();
    harness.mockEventChannel(1);
    harness.install(
      onCall: (call) async {
        if (call.method == 'setSource') {
          started.complete();
          return pending.future;
        }
        return null;
      },
    );
    await harness.attachController(controller, 1);
    final first = capture(controller.setMedia(a));
    await started.future;
    final second = capture(controller.setMedia(b));
    controller.dispose();
    pending.complete(null);
    await first;
    expect(await second, isA<StateError>());
    expect(
      harness.calls.where((call) => call.method == 'setSource'),
      hasLength(1),
    );
  });

  test(
    'an obsolete auto advance error cannot mark newer media as failed',
    () async {
      final pending = Completer<Object?>();
      final started = Completer<void>();
      var block = false;
      harness.mockEventChannel(1);
      harness.install(
        onCall: (call) async {
          if (block && call.method == 'setSource') {
            block = false;
            started.complete();
            return pending.future;
          }
          return null;
        },
      );
      await harness.attachController(controller, 1);
      await controller.setPlaylist([a, b]);
      block = true;
      await harness.sendEvent(1, {'state': 'ended'});
      await started.future;
      final newer = controller.setMedia(c);
      pending.completeError(PlatformException(code: 'load_failed'));
      await newer;
      expect(controller.currentMediaSource, c);
      expect(controller.value.hasError, isFalse);
    },
  );
  test(
    'an ended listener selecting new media suppresses stale auto advance',
    () async {
      harness.mockEventChannel(1);
      await harness.attachController(controller, 1);
      await controller.setPlaylist([a, b]);
      Future<void>? replacement;
      controller.addListener(() {
        if (controller.value.state == VlcPlaybackState.ended &&
            replacement == null) {
          replacement = controller.setMedia(c);
        }
      });
      await harness.sendEvent(1, {'state': 'ended'});
      await replacement;
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentMediaSource, c);
      expect(controller.value.hasError, isFalse);
      expect(
        harness.calls.where(
          (call) =>
              call.method == 'setSource' &&
              (call.arguments as Map)['uri'] == b.uri.toString(),
        ),
        isEmpty,
      );
    },
  );
}

Future<Object?> capture<T>(Future<T> operation) =>
    operation.then<Object?>((value) => value, onError: (Object error) => error);
