import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vlc_player/vlc_player.dart';

void main() {
  group('VlcPlayerValue', () {
    test('defaults remain backward compatible', () {
      const value = VlcPlayerValue();

      expect(value.state, VlcPlaybackState.idle);
      expect(value.position, Duration.zero);
      expect(value.duration, Duration.zero);
      expect(value.volume, 100);
      expect(value.playbackSpeed, 1);
      expect(value.isReady, isFalse);
      expect(value.isSeekable, isFalse);
      expect(value.isLive, isFalse);
      expect(value.videoSize, isNull);
      expect(value.bufferingProgress, isNull);
      expect(value.error, isNull);
      expect(value.errorDescription, isNull);
    });

    test('parses readiness, seekability, live, video size, and buffering', () {
      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'buffering',
        'position': 1200,
        'duration': 10000,
        'volume': 80,
        'playbackSpeed': 1.25,
        'isReady': false,
        'isSeekable': true,
        'isLive': false,
        'videoSize': <String, Object?>{'width': 1920, 'height': 1080},
        'bufferingProgress': 0.42,
      }, const VlcPlayerValue());

      expect(value.state, VlcPlaybackState.buffering);
      expect(value.position, const Duration(milliseconds: 1200));
      expect(value.duration, const Duration(seconds: 10));
      expect(value.volume, 80);
      expect(value.playbackSpeed, 1.25);
      expect(value.isReady, isFalse);
      expect(value.isSeekable, isTrue);
      expect(value.isLive, isFalse);
      expect(value.videoSize, const Size(1920, 1080));
      expect(value.bufferingProgress, 0.42);
    });

    test('keeps optional fields when an event omits them', () {
      const previous = VlcPlayerValue(
        state: VlcPlaybackState.playing,
        isReady: true,
        isSeekable: true,
        isLive: false,
        videoSize: Size(1280, 720),
      );

      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'position': 5000,
      }, previous);

      expect(value.state, VlcPlaybackState.playing);
      expect(value.position, const Duration(seconds: 5));
      expect(value.isReady, isTrue);
      expect(value.isSeekable, isTrue);
      expect(value.isLive, isFalse);
      expect(value.videoSize, const Size(1280, 720));
    });

    test('derives readiness from playback state when native omits it', () {
      final playing = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'playing',
      }, const VlcPlayerValue());
      final buffering = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'buffering',
      }, playing);

      expect(playing.isReady, isTrue);
      expect(buffering.isReady, isFalse);
    });

    test('clears stale video size when a new source starts opening', () {
      const previous = VlcPlayerValue(
        state: VlcPlaybackState.playing,
        videoSize: Size(1920, 1080),
      );

      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'opening',
      }, previous);

      expect(value.videoSize, isNull);
    });

    test('ignores invalid duration, position, size, and progress values', () {
      const previous = VlcPlayerValue(
        position: Duration(seconds: 3),
        duration: Duration(seconds: 30),
        videoSize: Size(640, 360),
        bufferingProgress: 0.5,
      );

      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'buffering',
        'position': -1,
        'duration': -1,
        'videoSize': <String, Object?>{'width': 0, 'height': 360},
        'bufferingProgress': double.nan,
      }, previous);

      expect(value.position, const Duration(seconds: 3));
      expect(value.duration, const Duration(seconds: 30));
      expect(value.videoSize, isNull);
      expect(value.bufferingProgress, isNull);
    });

    test('clamps buffering progress to a normalized range', () {
      final low = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'buffering',
        'bufferingProgress': -0.5,
      }, const VlcPlayerValue());
      final high = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'buffering',
        'bufferingProgress': 2,
      }, const VlcPlayerValue());

      expect(low.bufferingProgress, 0);
      expect(high.bufferingProgress, 1);
    });

    test('clears buffering progress outside buffering state', () {
      const previous = VlcPlayerValue(
        state: VlcPlaybackState.buffering,
        bufferingProgress: 0.5,
      );

      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'playing',
      }, previous);

      expect(value.bufferingProgress, isNull);
    });

    test('parses structured playback errors and keeps errorDescription', () {
      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'error',
        'errorCode': 'playback_error',
        'errorDescription': 'VLC failed',
        'errorDetails': <String, Object?>{'state': 'error'},
      }, const VlcPlayerValue());

      expect(value.state, VlcPlaybackState.error);
      expect(value.error, isNotNull);
      expect(value.error!.code, VlcPlayerErrorCode.playbackError);
      expect(value.error!.message, 'VLC failed');
      expect(value.error!.details, <String, Object?>{'state': 'error'});
      expect(value.errorDescription, 'VLC failed');
      expect(value.hasError, isTrue);
    });

    test('parses nested error payloads', () {
      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'error',
        'error': <Object?, Object?>{
          'code': 'set_source_failed',
          'message': 'Bad media',
        },
      }, const VlcPlayerValue());

      expect(value.error!.code, VlcPlayerErrorCode.setSourceFailed);
      expect(value.error!.message, 'Bad media');
      expect(value.errorDescription, 'Bad media');
    });

    test('clears structured errors on a normal event', () {
      const previous = VlcPlayerValue(
        state: VlcPlaybackState.error,
        error: VlcPlayerError(
          code: VlcPlayerErrorCode.playbackError,
          message: 'VLC failed',
        ),
        errorDescription: 'VLC failed',
      );

      final value = VlcPlayerValue.fromEvent(<String, Object?>{
        'state': 'playing',
      }, previous);

      expect(value.error, isNull);
      expect(value.errorDescription, isNull);
    });
  });
}
